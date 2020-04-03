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
	
	void initWindow() {
		glfwInit();
		
		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
		
		window = glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
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
		createGraphicsPipeline();
	}
	
	void mainLoop() {
		while (!glfwWindowShouldClose(window)) {
			glfwPollEvents();
		}
	}
	
	void cleanup() {
		foreach (imageView; swapChainImageViews) {
			vkDestroyImageView(device, imageView, null);
		}
		vkDestroySwapchainKHR(device, swapChain, null);
		vkDestroyDevice(device,null);
		debug destroyDebugUtilsMessengerEXT(instance, debugMessenger, null);
		vkDestroySurfaceKHR(instance, surface, null);
		vkDestroyInstance(instance, null);
		glfwDestroyWindow(window);
		glfwTerminate();
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
			
			oldSwapchain: VK_NULL_HANDLE,
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
		
		vkDestroyShaderModule(device, fragShaderModule, null);
		vkDestroyShaderModule(device, vertShaderModule, null);
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
			VkExtent2D actualExtent = {WIDTH, HEIGHT};
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

