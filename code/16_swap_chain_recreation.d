/+ dub.sdl:
dependency "derelict-glfw3" version="~>4.0.0-beta"
dependency "erupted" version="~>2.0.54"
+/
module main;

import std.stdio;
import std.algorithm.comparison;
import std.string;
import std.typecons: Nullable;
import std.container.rbtree;
import erupted;
import derelict.glfw3;
mixin DerelictGLFW3_VulkanBind;

enum int WIDTH = 800;
enum int HEIGHT = 600;
enum int MAX_FRAMES_IN_FLIGHT = 2;
debug immutable char*[] validationLayers = [
	"VK_LAYER_KHRONOS_validation",
];
immutable char*[] deviceExtensions = [
	VK_KHR_SWAPCHAIN_EXTENSION_NAME,
];

struct QueueFamilyIndices {
	Nullable!uint graphicsFamily;
	Nullable!uint presentFamily;
	
	bool isComplete() {
		return !graphicsFamily.isNull && !presentFamily.isNull;
	}
}
struct SwapChainSupportDetails {
	VkSurfaceCapabilitiesKHR capabilities;
	VkSurfaceFormatKHR[] formats;
	VkPresentModeKHR[] presentModes;
}

class HelloTriangleApplication {
public:
	void run() {
		initWindow();
		initVulkan();
		mainLoop();
		cleanup();
	}
	
private:
	GLFWwindow* window;
	
	VkInstance instance;
	debug VkDebugUtilsMessengerEXT debugMessenger;
	VkSurfaceKHR surface;
	
	VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
	VkDevice device;
	
	VkQueue graphicsQueue;
	VkQueue presentQueue;
	
	VkSwapchainKHR swapChain;
	VkImage[] swapChainImages;
	VkFormat swapChainImageFormat;
	VkExtent2D swapChainExtent;
	VkImageView[] swapChainImageViews;
	VkFramebuffer[] swapChainFramebuffers;
	
	VkRenderPass renderPass;
	VkPipelineLayout pipelineLayout;
	VkPipeline graphicsPipeline;
	
	VkCommandPool commandPool;
	VkCommandBuffer[] commandBuffers;
	
	VkSemaphore[] imageAvailableSemaphores;
	VkSemaphore[] renderFinishedSemaphores;
	VkFence[] inFlightFences;
	VkFence[] imagesInFlight;
	size_t currentFrame = 0;
	
	bool framebufferResized = false;
	
	void initWindow() {
		glfwInit();
		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
		window = glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
		glfwSetWindowUserPointer(window, cast(void*)this);
		glfwSetFramebufferSizeCallback(window, &framebufferResizeCallback);
	}
	
	void initVulkan() {
		loadGlobalLevelFunctions(cast( typeof( vkGetInstanceProcAddr )) glfwGetInstanceProcAddress( null, "vkGetInstanceProcAddr" ));
		createInstance();
		loadInstanceLevelFunctions(instance);
		loadDeviceLevelFunctions(instance);
		debug setupDebugMessenger();
		createSurface();
		pickPhysicalDevice();
		createLogicalDevice();
		createSwapChain();
		createImageViews();
		createRenderPass();
		createGraphicsPipeline();
		createFramebuffers();
		createCommandPool();
		createCommandBuffers();
		createSyncObjects();
	}
	
	void mainLoop() {
		while (!glfwWindowShouldClose(window)) {
			glfwPollEvents();
			drawFrame();
		}
		vkDeviceWaitIdle(device);
	}
	
	void cleanup() {
		cleanupSwapChain();
		foreach (i; 0..MAX_FRAMES_IN_FLIGHT) {
			vkDestroySemaphore(device, renderFinishedSemaphores[i], null);
			vkDestroySemaphore(device, imageAvailableSemaphores[i], null);
			vkDestroyFence(device, inFlightFences[i], null);
		}
		vkDestroyCommandPool(device, commandPool, null);
		vkDestroyDevice(device,null);
		debug destroyDebugUtilsMessengerEXT(instance, debugMessenger, null);
		vkDestroySurfaceKHR(instance, surface, null);
		vkDestroyInstance(instance, null);
		glfwDestroyWindow(window);
		glfwTerminate();
	}
	void cleanupSwapChain() {
		foreach (framebuffer; swapChainFramebuffers)
			vkDestroyFramebuffer(device, framebuffer, null);
		vkFreeCommandBuffers(device, commandPool, cast(uint) commandBuffers.length, commandBuffers.ptr);
		vkDestroyPipeline(device, graphicsPipeline, null);
		vkDestroyPipelineLayout(device, pipelineLayout, null);
		vkDestroyRenderPass(device, renderPass, null);
		foreach (imageView; swapChainImageViews) {
			vkDestroyImageView(device, imageView, null);
		}
		vkDestroySwapchainKHR(device, swapChain, null);
	}
	
	void createInstance() {
		debug if (!checkValidationLayerSupport()) {
			throw new Exception("Validation layers requested, but not available!");
		}
		
		VkApplicationInfo appInfo = {
			pApplicationName: "Hello Triangle",
			applicationVersion: VK_MAKE_VERSION(1, 0, 0),
			pEngineName: "No Engine",
			engineVersion: VK_MAKE_VERSION(1, 0, 0),
			apiVersion: VK_API_VERSION_1_0,
		};
		
		auto extensions = getRequiredExtensions();
		
		VkInstanceCreateInfo createInfo = {
			pApplicationInfo: (&appInfo),
			enabledExtensionCount: cast(uint)extensions.length,
			ppEnabledExtensionNames: extensions.ptr,
			enabledLayerCount: 0,
			pNext: null,
		};
		debug {
			createInfo.enabledLayerCount = cast(uint)validationLayers.length;
			createInfo.ppEnabledLayerNames = validationLayers.ptr;
			
			VkDebugUtilsMessengerCreateInfoEXT debugCreateInfo = getDebugCreateInfo();
			createInfo.pNext = &debugCreateInfo;
		}
		
		if (vkCreateInstance(&createInfo, null, &instance) != VK_SUCCESS) {
			throw new Exception("Failed to create instance!");
		}
	}
	
	QueueFamilyIndices findQueueFamilies(VkPhysicalDevice device) {
		QueueFamilyIndices indices;
		
		uint queueFamilyCount = 0;
		vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
		VkQueueFamilyProperties[] queueFamilies = new VkQueueFamilyProperties[queueFamilyCount];
		vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
		
		foreach (i, queueFamily; queueFamilies) {
			if (queueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT) {
				indices.graphicsFamily = cast(uint) i;
			}
			
			VkBool32 presentSupport = false;
			vkGetPhysicalDeviceSurfaceSupportKHR(device, cast(uint) i, surface, &presentSupport);
			if (presentSupport) {
				indices.presentFamily = cast(uint) i;
			}
			
			if (indices.isComplete())
				break;
		}
		
		return indices;
	}
	
	const(char)*[] getRequiredExtensions() {
		uint glfwExtensionCount = 0;
		const(char)** glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);
		const(char)*[] extensions = glfwExtensions[0..glfwExtensionCount];
		debug extensions ~= VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
		return extensions;
	}
	
	void createSurface() {
		if (glfwCreateWindowSurface(instance, window, null, &surface) != VK_SUCCESS) {
			throw new Exception("Failed to create window surface!");
		}
	}
	
	void pickPhysicalDevice() {
		bool isDeviceSuitable(VkPhysicalDevice device) {
			return findQueueFamilies(device).isComplete();
		}
		
		uint deviceCount = 0;
		vkEnumeratePhysicalDevices(instance, &deviceCount, null);
		if (deviceCount == 0)
			throw new Exception("Failed to find GPUs with Vulkan support!");
		VkPhysicalDevice[] devices = new VkPhysicalDevice[deviceCount];
		vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr);
		
		foreach (device; devices) {
			if (isDeviceSuitable(device)) {
				physicalDevice = device;
				return;
			}
		}
		throw new Exception("Failed to find a suitable GPU!");
	}
	void createLogicalDevice() {
		QueueFamilyIndices indices = findQueueFamilies(physicalDevice);
		
		auto queueCreateInfos = new VkDeviceQueueCreateInfo[0];
		
		auto uniqueQueueFamilies = redBlackTree(indices.graphicsFamily.get, indices.presentFamily.get);
		float queuePriority = 1.0;
		foreach (uint queueFamily; uniqueQueueFamilies) {
			VkDeviceQueueCreateInfo createInfo = {
				queueFamilyIndex: queueFamily,
				queueCount: 1,
				pQueuePriorities: &queuePriority,
			};
			queueCreateInfos ~= createInfo;
		}
		
		VkPhysicalDeviceFeatures deviceFeatures = {};
		
		VkDeviceCreateInfo createInfo = {
			queueCreateInfoCount: cast(uint) queueCreateInfos.length,
			pQueueCreateInfos: queueCreateInfos.ptr,
			pEnabledFeatures: (&deviceFeatures),
			enabledLayerCount: 0,
			enabledExtensionCount: cast(uint) deviceExtensions.length,
			ppEnabledExtensionNames: deviceExtensions.ptr,
		};
		debug {
			createInfo.enabledLayerCount = cast(uint) validationLayers.length;
			createInfo.ppEnabledLayerNames = validationLayers.ptr;
		}
		
		if (vkCreateDevice(physicalDevice, &createInfo, null, &device) != VK_SUCCESS) {
			throw new Exception("failed to create logical device!");
		}
		vkGetDeviceQueue(device, indices.graphicsFamily.get, 0, &graphicsQueue);
		vkGetDeviceQueue(device, indices.presentFamily.get, 0, &presentQueue);
	}
	
	void createSwapChain() {
		SwapChainSupportDetails swapChainSupport = querySwapChainSupport(physicalDevice);
		
		VkSurfaceFormatKHR surfaceFormat = chooseSwapSurfaceFormat(swapChainSupport.formats);
		VkPresentModeKHR presentMode = chooseSwapPresentMode(swapChainSupport.presentModes);
		VkExtent2D extent = chooseSwapExtent(swapChainSupport.capabilities);
		
		uint imageCount = swapChainSupport.capabilities.minImageCount + 1;
		if (swapChainSupport.capabilities.maxImageCount > 0 && imageCount > swapChainSupport.capabilities.maxImageCount) {
			imageCount = swapChainSupport.capabilities.maxImageCount;
		}
		
		VkSwapchainCreateInfoKHR createInfo = {
			surface: surface,
			minImageCount: imageCount,
			imageFormat: surfaceFormat.format,
			imageColorSpace: surfaceFormat.colorSpace,
			imageExtent: extent,
			imageArrayLayers: 1,
			imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
			
			preTransform: swapChainSupport.capabilities.currentTransform,
			compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
			presentMode: presentMode,
			clipped: VK_TRUE,
		};
		
		QueueFamilyIndices indices = findQueueFamilies(physicalDevice);
		uint[2] queueFamilyIndices = [indices.graphicsFamily.get, indices.presentFamily.get];
		
		if (indices.graphicsFamily != indices.presentFamily) {
			createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
			createInfo.queueFamilyIndexCount = 2;
			createInfo.pQueueFamilyIndices = queueFamilyIndices.ptr;
		}
		else {
			createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
		}
		
		if (vkCreateSwapchainKHR(device, &createInfo, null, &swapChain) != VK_SUCCESS) {
			throw new Exception("Failed to create swap chain!");
		}
		
		vkGetSwapchainImagesKHR(device, swapChain, &imageCount, null);
		swapChainImages = new VkImage[imageCount];
		vkGetSwapchainImagesKHR(device, swapChain, &imageCount, swapChainImages.ptr);
		
		swapChainImageFormat = surfaceFormat.format;
		swapChainExtent = extent;
	}
	void recreateSwapChain() {
		int width = 0, height = 0;
		glfwGetFramebufferSize(window, &width, &height);
		while (width == 0 || height == 0) {
			glfwGetFramebufferSize(window, &width, &height);
			glfwWaitEvents();
		}
		vkDeviceWaitIdle(device);
		cleanupSwapChain();
		createSwapChain();
		createImageViews();
		createRenderPass();
		createGraphicsPipeline();
		createFramebuffers();
		createCommandBuffers();
	}
	void createImageViews() {
		swapChainImageViews = new VkImageView[swapChainImages.length];
		
		foreach (i, swapChainImage; swapChainImages) {
			VkImageViewCreateInfo createInfo = {
				image: swapChainImage,
				viewType: VK_IMAGE_VIEW_TYPE_2D,
				format: swapChainImageFormat,
				components: {
					r: VK_COMPONENT_SWIZZLE_IDENTITY,
					g: VK_COMPONENT_SWIZZLE_IDENTITY,
					b: VK_COMPONENT_SWIZZLE_IDENTITY,
					a: VK_COMPONENT_SWIZZLE_IDENTITY,
				},
				subresourceRange: {
					aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
					baseMipLevel: 0,
					levelCount: 1,
					baseArrayLayer: 0,
					layerCount: 1,
				},
			};
			
			if (vkCreateImageView(device, &createInfo, null, &swapChainImageViews[i]) != VK_SUCCESS) {
				throw new Exception("Failed to create image views!");
			}
		}
	}
	void createRenderPass() {
		VkAttachmentDescription colorAttachment = {
			format: swapChainImageFormat,
			samples: VK_SAMPLE_COUNT_1_BIT,
			loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
			storeOp: VK_ATTACHMENT_STORE_OP_STORE,
			stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
			stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
			initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
			finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
		};
		VkAttachmentReference colorAttachmentRef = {
			attachment: 0,
			layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
		};
		VkSubpassDescription subpass = {
			pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
			colorAttachmentCount: 1,
			pColorAttachments: &colorAttachmentRef,
		};
		VkSubpassDependency dependency = {
			srcSubpass: VK_SUBPASS_EXTERNAL,
			dstSubpass: 0,
			srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
			srcAccessMask: 0,
			dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
			dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
		};
		VkRenderPassCreateInfo renderPassInfo = {
			attachmentCount: 1,
			pAttachments: &colorAttachment,
			subpassCount: 1,
			pSubpasses: &subpass,
			dependencyCount: 1,
			pDependencies: &dependency,
		};
		if (vkCreateRenderPass(device, &renderPassInfo, null, &renderPass) != VK_SUCCESS) {
			throw new Exception("Failed to create render pass!");
		}
	}
	void createGraphicsPipeline() {
		import std.file;
		uint[] vertShaderCode = cast(uint[]) read("shaders/vert.spv");
		uint[] fragShaderCode = cast(uint[]) read("shaders/frag.spv");
		
		VkShaderModule vertShaderModule = createShaderModule(vertShaderCode);
		VkShaderModule fragShaderModule = createShaderModule(fragShaderCode);
		
		VkPipelineShaderStageCreateInfo vertShaderStageInfo = {
			stage: VK_SHADER_STAGE_VERTEX_BIT,
			_module: vertShaderModule,
			pName: "main",
		};
		
		VkPipelineShaderStageCreateInfo fragShaderStageInfo = {
			stage: VK_SHADER_STAGE_FRAGMENT_BIT,
			_module: fragShaderModule,
			pName: "main",
		};
		
		VkPipelineShaderStageCreateInfo[] shaderStages = [vertShaderStageInfo, fragShaderStageInfo];
		
		VkPipelineVertexInputStateCreateInfo vertexInputInfo = {
			vertexBindingDescriptionCount: 0,
			vertexAttributeDescriptionCount: 0,
		};
		VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
			topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
			primitiveRestartEnable: VK_FALSE,
		};
		VkViewport viewport = {
			x: 0.0f,
			y: 0.0f,
			width: cast(float) swapChainExtent.width,
			height: cast(float) swapChainExtent.height,
			minDepth: 0.0f,
			maxDepth: 1.0f,
		};
		VkRect2D scissor = {
			offset: {0, 0},
			extent: swapChainExtent,
		};
		VkPipelineViewportStateCreateInfo viewportState = {
			viewportCount: 1,
			pViewports: &viewport,
			scissorCount: 1,
			pScissors: &scissor,
		};
		VkPipelineRasterizationStateCreateInfo rasterizer = {
			depthClampEnable: VK_FALSE,
			rasterizerDiscardEnable: VK_FALSE,
			polygonMode: VK_POLYGON_MODE_FILL,
			lineWidth: 1.0f,
			cullMode: VK_CULL_MODE_BACK_BIT,
			frontFace: VK_FRONT_FACE_CLOCKWISE,
			depthBiasEnable: VK_FALSE,
			depthBiasClamp: 0.0f,
		};
		VkPipelineMultisampleStateCreateInfo multisampling = {
			sampleShadingEnable: VK_FALSE,
			rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
		};
		VkPipelineColorBlendAttachmentState colorBlendAttachment = {
			colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
			blendEnable: VK_FALSE,
		};
		VkPipelineColorBlendStateCreateInfo colorBlending = {
			logicOpEnable: VK_FALSE,
			logicOp: VK_LOGIC_OP_COPY,
			attachmentCount: 1,
			pAttachments: &colorBlendAttachment,
			blendConstants: [0.0f,0.0f,0.0f,0.0f],
		};
		VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
			setLayoutCount: 0,
			pushConstantRangeCount: 0,
		};
		if (vkCreatePipelineLayout(device, &pipelineLayoutInfo, null, &pipelineLayout) != VK_SUCCESS) {
			throw new Exception("Failed to create pipeline layout!");
		}
		
		VkGraphicsPipelineCreateInfo pipelineInfo = {
			stageCount: cast(uint) shaderStages.length,
			pStages: shaderStages.ptr,
			pVertexInputState: &vertexInputInfo,
			pInputAssemblyState: &inputAssembly,
			pViewportState: &viewportState,
			pRasterizationState: &rasterizer,
			pMultisampleState: &multisampling,
			pColorBlendState: &colorBlending,
			layout: pipelineLayout,
			renderPass: renderPass,
			subpass: 0,
			basePipelineHandle: VK_NULL_HANDLE,
		};
		
		if (vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, null, &graphicsPipeline) != VK_SUCCESS) {
			throw new Exception("Failed to create graphics pipeline!");
		}
		
		vkDestroyShaderModule(device, fragShaderModule, null);
		vkDestroyShaderModule(device, vertShaderModule, null);
	}
	void createFramebuffers() {
		swapChainFramebuffers = new VkFramebuffer[swapChainImageViews.length];
		
		foreach (i, swapChainImageView; swapChainImageViews) {
			VkFramebufferCreateInfo framebufferInfo = {
				renderPass: renderPass,
				attachmentCount: 1,
				pAttachments: &swapChainImageView,
				width: swapChainExtent.width,
				height: swapChainExtent.height,
				layers: 1,
			};
			if (vkCreateFramebuffer(device, &framebufferInfo, null, &swapChainFramebuffers[i]) != VK_SUCCESS) {
				throw new Exception("Failed to create framebuffer!");
			}
		}
	}
	void createCommandPool() {
		QueueFamilyIndices queueFamilyIndices = findQueueFamilies(physicalDevice);
		VkCommandPoolCreateInfo poolInfo = {
			queueFamilyIndex: queueFamilyIndices.graphicsFamily.get,
		};
		if (vkCreateCommandPool(device, &poolInfo, null, &commandPool) != VK_SUCCESS) {
			throw new Exception("Failed to create command pool!");
		}
	}
	void createCommandBuffers() {
		commandBuffers = new VkCommandBuffer[swapChainFramebuffers.length];
		
		VkCommandBufferAllocateInfo allocInfo = {
			commandPool: commandPool,
			level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
			commandBufferCount: cast(uint) commandBuffers.length,
		};
		if (vkAllocateCommandBuffers(device, &allocInfo, commandBuffers.ptr) != VK_SUCCESS) {
			throw new Exception("Failed to allocate command buffers!");
		}
		
		foreach (i, commandBuffer; commandBuffers) {
			VkCommandBufferBeginInfo beginInfo = {};
			if (vkBeginCommandBuffer(commandBuffer, &beginInfo) != VK_SUCCESS) {
				throw new Exception("Failed to begin recording command buffer!");
			}
			VkClearValue clearColor = {VkClearColorValue([0.0f, 0.0f, 0.0f, 1.0f])};
			VkRenderPassBeginInfo renderPassInfo = {
				renderPass: renderPass,
				framebuffer: swapChainFramebuffers[i],
				renderArea: {
					offset: {0, 0},
					extent: swapChainExtent,
				},	
				clearValueCount: 1,
				pClearValues: &clearColor,
			};
			vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
				vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline);
				vkCmdDraw(commandBuffer, 3, 1, 0, 0);
			vkCmdEndRenderPass(commandBuffer);
			if (vkEndCommandBuffer(commandBuffer) != VK_SUCCESS) {
				throw new Exception("Failed to record command buffer!");
			}
		}
	}
	void createSyncObjects() {
		import std.algorithm.mutation:fill;
		imageAvailableSemaphores = new VkSemaphore[MAX_FRAMES_IN_FLIGHT];
		renderFinishedSemaphores = new VkSemaphore[MAX_FRAMES_IN_FLIGHT];
		inFlightFences = new VkFence[MAX_FRAMES_IN_FLIGHT];
		imagesInFlight = new VkFence[swapChainImages.length];
		imagesInFlight[] = VK_NULL_HANDLE;
		
		VkSemaphoreCreateInfo semaphoreInfo = {};
		VkFenceCreateInfo fenceInfo = {
			flags: VK_FENCE_CREATE_SIGNALED_BIT,
		};
		foreach (i; 0..MAX_FRAMES_IN_FLIGHT) {
			if (
				vkCreateSemaphore(device, &semaphoreInfo, null, &imageAvailableSemaphores[i]) != VK_SUCCESS
				|| vkCreateSemaphore(device, &semaphoreInfo, null, &renderFinishedSemaphores[i]) != VK_SUCCESS
				|| vkCreateFence(device, &fenceInfo, null, &inFlightFences[i]) != VK_SUCCESS
			) {
				throw new Exception("Failed to create synchronization objects for a frame!");
			}
		}
	}
	
	void drawFrame() {
		vkWaitForFences(device, 1, &inFlightFences[currentFrame], VK_TRUE, ulong.max);
		
		uint imageIndex;
		VkResult result = vkAcquireNextImageKHR(device, swapChain, ulong.max, imageAvailableSemaphores[currentFrame], VK_NULL_HANDLE, &imageIndex);
		if (result == VK_ERROR_OUT_OF_DATE_KHR) {
			recreateSwapChain();
			return;
		}
		else if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR) {
			throw new Exception("Failed to acquire swap chain image!");
		}
		
		if (imagesInFlight[imageIndex] != VK_NULL_HANDLE) {
			vkWaitForFences(device, 1, &imagesInFlight[imageIndex], VK_TRUE, ulong.max);
		}
		imagesInFlight[imageIndex] = inFlightFences[currentFrame];
		
		VkSemaphore waitSemaphore= imageAvailableSemaphores[currentFrame];
		VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
		VkSemaphore signalSemaphore = renderFinishedSemaphores[currentFrame];
		VkSubmitInfo submitInfo = {
			waitSemaphoreCount: 1,
			pWaitSemaphores: &waitSemaphore,
			pWaitDstStageMask: &waitStage,
			commandBufferCount: 1,
			pCommandBuffers: &commandBuffers[imageIndex],
			signalSemaphoreCount: 1,
			pSignalSemaphores: &signalSemaphore,
		};
		vkResetFences(device, 1, &inFlightFences[currentFrame]);
		
		if (vkQueueSubmit(graphicsQueue, 1, &submitInfo, inFlightFences[currentFrame]) != VK_SUCCESS) {
			throw new Exception("Failed to submit draw command buffer!");
		}
		
		VkPresentInfoKHR presentInfo = {
			waitSemaphoreCount: 1,
			pWaitSemaphores: &signalSemaphore,
			swapchainCount: 1,
			pSwapchains: &swapChain,
			pImageIndices: &imageIndex,
		};
		result = vkQueuePresentKHR(presentQueue, &presentInfo);
		if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR || framebufferResized) {
			framebufferResized = false;
			recreateSwapChain();
		}
		else if (result != VK_SUCCESS) {
			throw new Exception("Failed to present swap chain image!");
		}
		
		currentFrame = (currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
	}
	
	VkShaderModule createShaderModule(uint[] code) {
		assert((cast(size_t) code.ptr) % 4 == 0);
		VkShaderModuleCreateInfo createInfo = {
			codeSize: cast(uint) code.length*4,
			pCode: code.ptr,
		};
		
		VkShaderModule shaderModule;
		if (vkCreateShaderModule(device, &createInfo, null, &shaderModule) != VK_SUCCESS) {
			throw new Exception("Failed to create shader module!");
		}
		
		return shaderModule;
	}
	
	VkSurfaceFormatKHR chooseSwapSurfaceFormat(VkSurfaceFormatKHR[] availableFormats) {
		foreach (availableFormat; availableFormats) {
			if (availableFormat.format == VK_FORMAT_B8G8R8A8_SRGB && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
				return availableFormat;
			}
		}
		return availableFormats[0];
	}
	
	VkPresentModeKHR chooseSwapPresentMode(const VkPresentModeKHR[] availablePresentModes) {
		foreach (availablePresentMode; availablePresentModes) {
			if (availablePresentMode == VK_PRESENT_MODE_MAILBOX_KHR) {
				return availablePresentMode;
			}
		}
		return VK_PRESENT_MODE_FIFO_KHR;
	}
	
	VkExtent2D chooseSwapExtent(const VkSurfaceCapabilitiesKHR capabilities) {
		if (capabilities.currentExtent.width != uint.max) {
			return capabilities.currentExtent;
		}
		else {
			int width, height;
			glfwGetFramebufferSize(window, &width, &height);
			VkExtent2D actualExtent = {
				cast(uint) width,
				cast(uint) height,
			};
			actualExtent.width = max(capabilities.minImageExtent.width, min(capabilities.maxImageExtent.width, actualExtent.width));
			actualExtent.height = max(capabilities.minImageExtent.height, min(capabilities.maxImageExtent.height, actualExtent.height));
			return actualExtent;
		}
	}
	
	SwapChainSupportDetails querySwapChainSupport(VkPhysicalDevice device) {
		SwapChainSupportDetails details;
		
		vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities);
		
		uint formatCount;
		vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, null);
		
		if (formatCount != 0) {
			details.formats = new VkSurfaceFormatKHR[formatCount];
			vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, details.formats.ptr);
		}
		
		uint presentModeCount;
		vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, null);
		
		if (presentModeCount != 0) {
			details.presentModes = new VkPresentModeKHR[presentModeCount];
			vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, details.presentModes.ptr);
		}
		
		return details;
	}
	
	
	debug {
		VkDebugUtilsMessengerCreateInfoEXT getDebugCreateInfo() {
			VkDebugUtilsMessengerCreateInfoEXT debugCreateInfo =  {
				messageSeverity: VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
				messageType: VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
				pfnUserCallback: &debugCallback,
			};
			return debugCreateInfo;
		}
		void setupDebugMessenger() {
			VkDebugUtilsMessengerCreateInfoEXT createInfo = getDebugCreateInfo();
			if (createDebugUtilsMessengerEXT(instance, &createInfo, null, &debugMessenger) != VK_SUCCESS) {
				throw new Exception("Failed to set up debug messenger!");
			}
		}
		
		bool checkValidationLayerSupport() {
			uint layerCount;
			vkEnumerateInstanceLayerProperties(&layerCount, null);
			
			VkLayerProperties[] availableLayers = new VkLayerProperties[layerCount];
			vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);
			
			validationLayersLoop:
			foreach (layerName; validationLayers) {
				foreach (layerProperties; availableLayers) {
					if (layerName.fromStringz == layerProperties.layerName.ptr.fromStringz) {
						continue validationLayersLoop;
					}
				}
				return false; // This validation layer was not found in available layers.
			}
			return true;
		}
	}
};

void main() {
	
	DerelictGLFW3.load;
	DerelictGLFW3_loadVulkan();
	
	HelloTriangleApplication app = new HelloTriangleApplication();
	
	app.run();
}

debug {
	VkResult createDebugUtilsMessengerEXT(VkInstance instance, const VkDebugUtilsMessengerCreateInfoEXT* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkDebugUtilsMessengerEXT* pDebugMessenger) {
		auto func = cast(PFN_vkCreateDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
		if (func != null) {
			return func(instance, pCreateInfo, pAllocator, pDebugMessenger);
		} else {
			return VK_ERROR_EXTENSION_NOT_PRESENT;
		}
	}
	
	void destroyDebugUtilsMessengerEXT(VkInstance instance, VkDebugUtilsMessengerEXT debugMessenger, const VkAllocationCallbacks* pAllocator) {
		auto func = cast(PFN_vkDestroyDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
		if (func != null) {
			func(instance, debugMessenger, pAllocator);
		}
	}
	
	extern(C) nothrow @nogc
	VkBool32 debugCallback(VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity, VkDebugUtilsMessageTypeFlagsEXT messageType, const(VkDebugUtilsMessengerCallbackDataEXT)* pCallbackData, void* pUserData) {
		try {
			debug stderr.writeln("Validation layer: ", pCallbackData.pMessage.fromStringz);
		}
		catch(Throwable) {}
		return VK_FALSE;
	}
}

extern (C) nothrow
void framebufferResizeCallback(GLFWwindow* window, int width, int height) {
	auto app = cast(HelloTriangleApplication) cast(void*) (glfwGetWindowUserPointer(window));
	app.framebufferResized = true;
}

