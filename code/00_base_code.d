/+ dub.sdl:
dependency "derelict-glfw3" version="~>4.0.0-beta"
dependency "erupted" version="~>2.0.54"
+/
module main;

import std.stdio;
import erupted;
import derelict.glfw3;
mixin DerelictGLFW3_VulkanBind;

enum int WIDTH = 800;
enum int HEIGHT = 600;

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
	
	void initWindow() {
		glfwInit();
		
		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
		
		window = glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
	}
	
	void initVulkan() {
	
	}
	
	void mainLoop() {
		while (!glfwWindowShouldClose(window)) {
			glfwPollEvents();
		}
	}
	
	void cleanup() {
		glfwDestroyWindow(window);
		
		glfwTerminate();
	}
};

void main() {
	DerelictGLFW3.load;
	DerelictGLFW3_loadVulkan();
	
	HelloTriangleApplication app = new HelloTriangleApplication();
	
	app.run();
}
