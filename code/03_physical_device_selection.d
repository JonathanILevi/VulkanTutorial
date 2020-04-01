/+ dub.sdl:
dependency "derelict-glfw3" version="~>4.0.0-beta"
dependency "erupted" version="~>2.0.54"
+/
module main;

import std.stdio;
import std.string;
import std.typecons: Nullable;
import erupted;
import derelict.glfw3;
mixin DerelictGLFW3_VulkanBind;

enum int WIDTH = 800;
enum int HEIGHT = 600;
debug immutable char*[] validationLayers = [
	"VK_LAYER_KHRONOS_validation",
];

struct QueueFamilyIndices {
	Nullable!uint graphicsFamily;
	
	bool isComplete() {
		return !graphicsFamily.isNull;
	}
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
	VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
	
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
		debug setupDebugMessenger();
		pickPhysicalDevice();
	}
	
	void mainLoop() {
		while (!glfwWindowShouldClose(window)) {
			glfwPollEvents();
		}
	}
	
	void cleanup() {
		debug destroyDebugUtilsMessengerEXT(instance, debugMessenger, null);
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
	
	const(char)*[] getRequiredExtensions() {
		uint glfwExtensionCount = 0;
		const(char)** glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);
		const(char)*[] extensions = glfwExtensions[0..glfwExtensionCount];
		debug extensions ~= VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
		return extensions;
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

QueueFamilyIndices findQueueFamilies(VkPhysicalDevice device) {
	QueueFamilyIndices indices;
	
	uint queueFamilyCount = 0;
	vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
	VkQueueFamilyProperties[] queueFamilies = new VkQueueFamilyProperties[queueFamilyCount];
	vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
	
	foreach (i, queueFamily; queueFamilies) {
		if (queueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT) {
			indices.graphicsFamily = cast(uint) i;
			if (indices.isComplete())
				break;
		}
	}
	
	return indices;
}
