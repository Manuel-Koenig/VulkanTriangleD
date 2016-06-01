import erupted;

import std.exception;
import std.algorithm.searching;
import std.algorithm.iteration;
import std.range: iota;
import std.stdio;
import core.stdc.string;
import derelict.sdl2.sdl;

struct Vertex
{
	float x, y, z, w;
}

void enforceVk(VkResult res){
    import std.exception;
    import std.conv;
    enforce(res is VkResult.VK_SUCCESS, res.to!string);
}

static void PrintEvent(const SDL_Event* event)
{
    if (event.type == SDL_WINDOWEVENT) {
        switch (event.window.event) {
        case SDL_WINDOWEVENT_SHOWN:
            SDL_Log("Window %d shown", event.window.windowID);
            break;
        case SDL_WINDOWEVENT_HIDDEN:
            SDL_Log("Window %d hidden", event.window.windowID);
            break;
        case SDL_WINDOWEVENT_EXPOSED:
            SDL_Log("Window %d exposed", event.window.windowID);
            break;
        case SDL_WINDOWEVENT_MOVED:
            SDL_Log("Window %d moved to %d,%d",
                    event.window.windowID, event.window.data1,
                    event.window.data2);
            break;
        case SDL_WINDOWEVENT_RESIZED:
            SDL_Log("Window %d resized to %dx%d",
                    event.window.windowID, event.window.data1,
                    event.window.data2);
            break;
        case SDL_WINDOWEVENT_SIZE_CHANGED:
            SDL_Log("Window %d size changed to %dx%d",
                    event.window.windowID, event.window.data1,
                    event.window.data2);
            break;
        case SDL_WINDOWEVENT_MINIMIZED:
            SDL_Log("Window %d minimized", event.window.windowID);
            break;
        case SDL_WINDOWEVENT_MAXIMIZED:
            SDL_Log("Window %d maximized", event.window.windowID);
            break;
        case SDL_WINDOWEVENT_RESTORED:
            SDL_Log("Window %d restored", event.window.windowID);
            break;
        case SDL_WINDOWEVENT_ENTER:
            SDL_Log("Mouse entered window %d",
                    event.window.windowID);
            break;
        case SDL_WINDOWEVENT_LEAVE:
            SDL_Log("Mouse left window %d", event.window.windowID);
            break;
        case SDL_WINDOWEVENT_FOCUS_GAINED:
            SDL_Log("Window %d gained keyboard focus",
                    event.window.windowID);
            break;
        case SDL_WINDOWEVENT_FOCUS_LOST:
            SDL_Log("Window %d lost keyboard focus",
                    event.window.windowID);
            break;
        case SDL_WINDOWEVENT_CLOSE:
            SDL_Log("Window %d closed", event.window.windowID);
            break;
        default:
            SDL_Log("Window %d got unknown event %d",
                    event.window.windowID, event.window.event);
            break;
        }
    }
}

extern(System) VkBool32 MyDebugReportCallback(
    VkDebugReportFlagsEXT       flags,
    VkDebugReportObjectTypeEXT  objectType,
    uint64_t                    object,
    size_t                      location,
    int32_t                     messageCode,
    const char*                 pLayerPrefix,
    const char*                 pMessage,
    void*                       pUserData) nothrow @nogc
{
    import std.stdio;
    printf("ObjectTpye: %i  \n", objectType);
    printf(pMessage);
    printf("\n");
    return VK_FALSE;
}

struct VkContext
{
    VkInstance instance;
    VkSurfaceKHR surface;
    uint width = -1;
    uint height = -1;
    VkPhysicalDevice physicalDevice;
    uint32_t presentQueueFamilyIndex = -1;
    VkDevice logicalDevice;

    VkPhysicalDeviceMemoryProperties memoryProperties;
	VkDebugReportCallbackEXT callback;

    VkBuffer vertexInputBuffer;
	VkDeviceMemory vertexBufferMemory;
	VkShaderModule vertexShaderModule;
	VkShaderModule fragmentShaderModule;

	VkCommandPool commandPool;
    VkCommandBuffer setupCmdBuffer;
    VkCommandBuffer drawCmdBuffer;

	/* swapchain */
    VkQueue presentQueue;
	VkFormat colorFormat; // colorformat of the surface
	VkViewport viewport;
	VkRect2D scissors;
    VkSwapchainKHR swapchain;

	/* framebuffers */
    VkImage[] presentImages;
	VkImageView[] presentImageViews;
    VkImage depthImage;
    VkImageView depthImageView;
	VkDeviceMemory imageMemory;
    VkRenderPass renderPass;
    VkFramebuffer[] frameBuffers;

	/* pipeline */
    VkPipelineLayout pipelineLayout;
    VkPipeline pipeline;

    VkSemaphore presentCompleteSemaphore, renderingCompleteSemaphore;
	VkFence submitFence;

	const(char*)[1] validationLayers = ["VK_LAYER_LUNARG_standard_validation"];

	void createInstance()
	{
		VkApplicationInfo appinfo;
		appinfo.pApplicationName = "Breeze";
		appinfo.apiVersion = VK_MAKE_VERSION(1, 0, 2);

		const(char*)[3] extensionNames = [
			"VK_KHR_surface",
			"VK_KHR_xlib_surface",
			"VK_EXT_debug_report"
		];
		uint extensionCount = 0;
		vkEnumerateInstanceExtensionProperties(null, &extensionCount, null );

		auto extensionProps = new VkExtensionProperties[](extensionCount);
		vkEnumerateInstanceExtensionProperties(null, &extensionCount, extensionProps.ptr );

		enforce(extensionNames[].all!((extensionName){
			return extensionProps[].count!((extension){
				return strcmp(cast(const(char*))extension.extensionName, extensionName) == 0;
			}) > 0;
		}), "extension props failure");

		uint layerCount = 0;
		vkEnumerateInstanceLayerProperties(&layerCount, null);

		auto layerProps = new VkLayerProperties[](layerCount);
		vkEnumerateInstanceLayerProperties(&layerCount, layerProps.ptr);


		enforce(validationLayers[].all!((layerName){
			return layerProps[].count!((layer){
				return strcmp(cast(const(char*))layer.layerName, layerName) == 0;
			}) > 0;
		}), "Validation layer failure");

		VkInstanceCreateInfo createinfo;
		createinfo.pApplicationInfo = &appinfo;
		createinfo.enabledExtensionCount = cast(uint)extensionNames.length;
		createinfo.ppEnabledExtensionNames = extensionNames.ptr;
		createinfo.enabledLayerCount = validationLayers.length;
		createinfo.ppEnabledLayerNames = validationLayers.ptr;

		enforceVk(vkCreateInstance(&createinfo, null, &instance));
		loadInstanceLevelFunctions(instance);
	}

	void createDebugReportCallback()
	{
		auto debugcallbackCreateInfo = VkDebugReportCallbackCreateInfoEXT(
			VkStructureType.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
			null,
			VkDebugReportFlagBitsEXT.VK_DEBUG_REPORT_ERROR_BIT_EXT |
			VkDebugReportFlagBitsEXT.VK_DEBUG_REPORT_WARNING_BIT_EXT |
			VkDebugReportFlagBitsEXT.VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT,
			&MyDebugReportCallback,
			null
		);
		enforceVk(vkCreateDebugReportCallbackEXT(instance, &debugcallbackCreateInfo, null, &callback));
	}

	void createSurface(SDL_SysWMinfo sdlWindowInfo)
	{
		auto xlibInfo = VkXlibSurfaceCreateInfoKHR(
			VkStructureType.VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
			null,
			0,
			sdlWindowInfo.info.x11.display,
			sdlWindowInfo.info.x11.window
		);
		enforceVk(vkCreateXlibSurfaceKHR(instance, &xlibInfo, null, &surface));
	}

	void createDevice()
	{
		uint numOfDevices;
		enforceVk(vkEnumeratePhysicalDevices(instance, &numOfDevices, null));

		auto devices = new VkPhysicalDevice[](numOfDevices);
		enforceVk(vkEnumeratePhysicalDevices(instance, &numOfDevices, devices.ptr));

		const(char*)[1] deviceExtensions = ["VK_KHR_swapchain"];

		foreach(index, device; devices){
			VkPhysicalDeviceProperties props;

			vkGetPhysicalDeviceProperties(device, &props);
			if(props.deviceType is VkPhysicalDeviceType.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU){
				uint queueCount = 0;
				vkGetPhysicalDeviceQueueFamilyProperties(device, &queueCount, null);
				enforce(queueCount > 0);
				auto queueFamilyProp = new VkQueueFamilyProperties[](queueCount);
				vkGetPhysicalDeviceQueueFamilyProperties(device, &queueCount, queueFamilyProp.ptr);

				uint32_t presentIndex = cast(uint32_t) queueFamilyProp[].countUntil!((prop){
					return prop.queueCount > 0 && (prop.queueFlags & VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT);
				});

				VkBool32 supportsPresent;
				vkGetPhysicalDeviceSurfaceSupportKHR(
					device, presentIndex,
					surface, &supportsPresent
				);

				if(presentIndex != -1 && supportsPresent){
					presentQueueFamilyIndex = presentIndex;
					physicalDevice = device;
					break;
				}
			}
		}

		enforce(
			presentQueueFamilyIndex !is -1 &&
			physicalDevice,
			"Could not find a suitable device"
		);

		uint extensionDeviceCount = 0;
		vkEnumerateDeviceExtensionProperties(physicalDevice, null, &extensionDeviceCount, null);
		auto extensionDeviceProps = new VkExtensionProperties[](extensionDeviceCount);

		vkEnumerateDeviceExtensionProperties(physicalDevice, null, &extensionDeviceCount, extensionDeviceProps.ptr);

		enforce(physicalDevice != null, "Device is null");
		//enforce the swapchain
		enforce(extensionDeviceProps[].map!(prop => prop.extensionName).count!((name){
					return strcmp(cast(const(char*))name, "VK_KHR_swapchain" ) == 0;
		}) > 0);

		float[1] priorities = [1.0f];
		VkDeviceQueueCreateInfo deviceQueueCreateInfo =
			VkDeviceQueueCreateInfo(
				VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
				null,
				0,
				cast(uint32_t)presentQueueFamilyIndex,
				cast(uint32_t)priorities.length,
				priorities.ptr
		);

		VkPhysicalDeviceFeatures features;
		features.shaderClipDistance = VK_TRUE;

		auto deviceInfo = VkDeviceCreateInfo(
			VkStructureType.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
			null,
			0,
			1,
			&deviceQueueCreateInfo,
			validationLayers.length,
			validationLayers.ptr,
			cast(uint)deviceExtensions.length,
			deviceExtensions.ptr,
			&features
		);
		enforceVk(vkCreateDevice(physicalDevice, &deviceInfo, null, &logicalDevice));

		loadDeviceLevelFunctions(logicalDevice);

		vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memoryProperties);

		VkFenceCreateInfo fenceCreateInfo;
		vkCreateFence(logicalDevice, &fenceCreateInfo, null, &submitFence);
	}

	void createSwapchain()
	{
		VkQueue queue;
		vkGetDeviceQueue(logicalDevice, cast(uint)presentQueueFamilyIndex, 0, &presentQueue);

		uint formatCount = 0;
		vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &formatCount, null);
		enforce(formatCount > 0, "Format failed");
		auto surfaceFormats = new VkSurfaceFormatKHR[](formatCount);
		vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &formatCount, surfaceFormats.ptr);

		if(surfaceFormats[0].format is VK_FORMAT_UNDEFINED)
			colorFormat = VK_FORMAT_B8G8R8_UNORM;
		else
			colorFormat = surfaceFormats[0].format;

		VkColorSpaceKHR colorSpace;
		colorSpace = surfaceFormats[0].colorSpace;

		VkSurfaceCapabilitiesKHR surfaceCapabilities;
		vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, &surfaceCapabilities);

		uint desiredImageCount = 2;
		if( desiredImageCount < surfaceCapabilities.minImageCount )
			desiredImageCount = surfaceCapabilities.minImageCount;
		else if(surfaceCapabilities.maxImageCount != 0 &&
		        desiredImageCount > surfaceCapabilities.maxImageCount )
			desiredImageCount = surfaceCapabilities.maxImageCount;

		VkExtent2D surfaceResolution = surfaceCapabilities.currentExtent;

		if(surfaceResolution.width is -1)
		{
			surfaceResolution.width = width;
			surfaceResolution.height = height;
		}
		else
		{
			width = surfaceResolution.width;
			height = surfaceResolution.height;
		}

		VkSurfaceTransformFlagBitsKHR preTransform = surfaceCapabilities.currentTransform;
		if(surfaceCapabilities.supportedTransforms & VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR){
			preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
		}

		uint presentModeCount = 0;
		vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &presentModeCount, null);
		auto presentModes = new VkPresentModeKHR[](presentModeCount);
		vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &presentModeCount, presentModes.ptr);

		VkPresentModeKHR presentMode = VK_PRESENT_MODE_FIFO_KHR;
		foreach(mode; presentModes){
			if(mode is VK_PRESENT_MODE_MAILBOX_KHR){
				presentMode = mode;
				break;
			}
		}

		VkSwapchainCreateInfoKHR swapchainCreateInfo =
		{
			surface: surface,
			imageFormat: colorFormat,
			minImageCount: desiredImageCount,
			imageColorSpace: colorSpace,
			imageExtent: surfaceResolution,
			imageArrayLayers: 1,
			imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
			imageSharingMode: VkSharingMode.VK_SHARING_MODE_EXCLUSIVE,
			preTransform: preTransform,
			compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
			presentMode: presentMode,
			clipped: VK_TRUE,
			oldSwapchain: null
		};

		enforceVk(vkCreateSwapchainKHR(logicalDevice, &swapchainCreateInfo, null, &swapchain));
	}

	void createCommandPool()
	{
		VkCommandPoolCreateInfo commandPoolCreateInfo =
		{ flags : VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT };
		commandPoolCreateInfo.queueFamilyIndex = cast(uint32_t) presentQueueFamilyIndex;

		enforceVk(vkCreateCommandPool(logicalDevice, &commandPoolCreateInfo, null, &commandPool));
	}

	void allocateCommandBuffers()
	{
		VkCommandBufferAllocateInfo cmdBufferAllocateInfo =
		{
			commandPool:        commandPool,
			level:              VK_COMMAND_BUFFER_LEVEL_PRIMARY,
			commandBufferCount: 1
		};

		enforceVk(vkAllocateCommandBuffers(logicalDevice, &cmdBufferAllocateInfo, &setupCmdBuffer));
		enforceVk(vkAllocateCommandBuffers(logicalDevice, &cmdBufferAllocateInfo, &drawCmdBuffer));
	}

	void createFramebuffers()
	{
		uint imageCount = 0;
		vkGetSwapchainImagesKHR(logicalDevice, swapchain, &imageCount, null);
		presentImages = new VkImage[](imageCount);
		enforceVk(vkGetSwapchainImagesKHR(logicalDevice, swapchain, &imageCount, presentImages.ptr));

		VkImageViewCreateInfo imgViewCreateInfo;
		imgViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
		imgViewCreateInfo.format = colorFormat;
		imgViewCreateInfo.components =
			VkComponentMapping(
					VK_COMPONENT_SWIZZLE_R,
					VK_COMPONENT_SWIZZLE_G,
					VK_COMPONENT_SWIZZLE_B,
					VK_COMPONENT_SWIZZLE_A,
					);

		imgViewCreateInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
		imgViewCreateInfo.subresourceRange.baseMipLevel = 0;
		imgViewCreateInfo.subresourceRange.levelCount = 1;
		imgViewCreateInfo.subresourceRange.baseArrayLayer = 0;
		imgViewCreateInfo.subresourceRange.layerCount = 1;

		VkCommandBufferBeginInfo beginInfo;
		beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

		presentImageViews = new VkImageView[](imageCount);
		foreach(index; 0 .. imageCount)
		{
			imgViewCreateInfo.image = presentImages[index];
			enforceVk(vkCreateImageView(logicalDevice, &imgViewCreateInfo, null, &presentImageViews[index]));
		}

		VkImageCreateInfo imageCreateInfo;
		imageCreateInfo.imageType = VK_IMAGE_TYPE_2D;
		imageCreateInfo.format = VK_FORMAT_D16_UNORM;
		imageCreateInfo.extent = VkExtent3D(width, height, 1);
		imageCreateInfo.mipLevels = 1;
		imageCreateInfo.arrayLayers = 1;
		imageCreateInfo.samples = VK_SAMPLE_COUNT_1_BIT;
		imageCreateInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
		imageCreateInfo.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
		imageCreateInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
		imageCreateInfo.queueFamilyIndexCount = 0;
		imageCreateInfo.pQueueFamilyIndices = null;
		imageCreateInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

		enforceVk(vkCreateImage(logicalDevice, &imageCreateInfo, null, &depthImage));

		VkMemoryRequirements memoryRequirements;
		vkGetImageMemoryRequirements(logicalDevice, depthImage, &memoryRequirements);

		VkMemoryAllocateInfo imageAllocationInfo;
		imageAllocationInfo.allocationSize = memoryRequirements.size;

		auto memoryTypeBits = memoryRequirements.memoryTypeBits;
		VkMemoryPropertyFlags desiredMemoryFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;

		foreach(index; 0 .. 32)
		{
			VkMemoryType memoryType = memoryProperties.memoryTypes[index];
			if(memoryTypeBits & 1){
				if((memoryType.propertyFlags & desiredMemoryFlags) is desiredMemoryFlags){
					imageAllocationInfo.memoryTypeIndex = index;
					break;
				}
			}
			memoryTypeBits = memoryTypeBits >> 1;
		}

		enforceVk(vkAllocateMemory(logicalDevice, &imageAllocationInfo, null, &imageMemory));

		enforceVk(vkBindImageMemory(logicalDevice, depthImage, imageMemory, 0));

		vkBeginCommandBuffer(setupCmdBuffer, &beginInfo);
		VkImageMemoryBarrier layoutTransitionBarrier;
		layoutTransitionBarrier.srcAccessMask = 0;
		layoutTransitionBarrier.dstAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT |
			VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
		layoutTransitionBarrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
		layoutTransitionBarrier.newLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		layoutTransitionBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
		layoutTransitionBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
		layoutTransitionBarrier.image = depthImage;
		layoutTransitionBarrier.subresourceRange = VkImageSubresourceRange(VK_IMAGE_ASPECT_DEPTH_BIT, 0, 1, 0, 1);

		vkCmdPipelineBarrier(
				setupCmdBuffer,
				VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
				VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
				0,
				0, null,
				0, null,
				1, &layoutTransitionBarrier
				);

		vkEndCommandBuffer(setupCmdBuffer);

		VkPipelineStageFlags[1] waitStageMask = [ VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT ];
		VkSubmitInfo submitInfo;
		submitInfo.waitSemaphoreCount = 0;
		submitInfo.pWaitSemaphores = null;
		submitInfo.pWaitDstStageMask = waitStageMask.ptr;
		submitInfo.commandBufferCount = 1;
		submitInfo.pCommandBuffers = &setupCmdBuffer;
		submitInfo.signalSemaphoreCount = 0;
		submitInfo.pSignalSemaphores = null;

		SDL_Log("0");
		vkResetFences(logicalDevice, 1, &submitFence);
		SDL_Log("a");
		vkQueueSubmit(presentQueue, 1, &submitInfo, submitFence);
		SDL_Log("b");

		enforceVk(vkWaitForFences(logicalDevice, 1, &submitFence, VK_TRUE, ulong.max));
		SDL_Log("c");
		vkResetFences(logicalDevice, 1, &submitFence);
		SDL_Log("d");
		vkResetCommandBuffer(setupCmdBuffer, 0);
		SDL_Log("e");

		VkImageAspectFlags aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
		VkImageViewCreateInfo imageViewCreateInfo;
		imageViewCreateInfo.image = depthImage;
		imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
		imageViewCreateInfo.format = imageCreateInfo.format;
		imageViewCreateInfo.components =
			VkComponentMapping(VK_COMPONENT_SWIZZLE_IDENTITY,
					VK_COMPONENT_SWIZZLE_IDENTITY,
					VK_COMPONENT_SWIZZLE_IDENTITY,
					VK_COMPONENT_SWIZZLE_IDENTITY
					);
		imageViewCreateInfo.subresourceRange.aspectMask = aspectMask;
		imageViewCreateInfo.subresourceRange.baseMipLevel = 0;
		imageViewCreateInfo.subresourceRange.levelCount = 1;
		imageViewCreateInfo.subresourceRange.baseArrayLayer = 0;
		imageViewCreateInfo.subresourceRange.layerCount = 1;

		enforceVk(vkCreateImageView(logicalDevice, &imageViewCreateInfo, null, &depthImageView));

		VkAttachmentDescription[2] passAttachments;
		passAttachments[0].format = colorFormat;
		passAttachments[0].samples = VK_SAMPLE_COUNT_1_BIT;
		passAttachments[0].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
		passAttachments[0].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
		passAttachments[0].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		passAttachments[0].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		passAttachments[0].initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
		passAttachments[0].finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

		passAttachments[1].format = VK_FORMAT_D16_UNORM;
		passAttachments[1].samples = VK_SAMPLE_COUNT_1_BIT;
		passAttachments[1].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
		passAttachments[1].storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		passAttachments[1].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		passAttachments[1].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		passAttachments[1].initialLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		passAttachments[1].finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

		VkAttachmentReference colorAttachmentReference;
		colorAttachmentReference.attachment = 0;
		colorAttachmentReference.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

		VkAttachmentReference depthAttachmentReference;
		depthAttachmentReference.attachment = 1;
		depthAttachmentReference.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

		VkSubpassDescription subpass;
		subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
		subpass.colorAttachmentCount = 1;
		subpass.pColorAttachments = &colorAttachmentReference;
		subpass.pDepthStencilAttachment = &depthAttachmentReference;

		VkRenderPassCreateInfo renderPassCreateInfo;
		renderPassCreateInfo.attachmentCount = 2;
		renderPassCreateInfo.pAttachments = passAttachments.ptr;
		renderPassCreateInfo.subpassCount = 1;
		renderPassCreateInfo.pSubpasses = &subpass;

		enforceVk(vkCreateRenderPass(logicalDevice, &renderPassCreateInfo, null, &renderPass));

		VkImageView[2] frameBufferAttachments;
		frameBufferAttachments[1] = depthImageView;

		VkFramebufferCreateInfo frameBufferCreateInfo;
		frameBufferCreateInfo.renderPass = renderPass;
		frameBufferCreateInfo.attachmentCount = 2;
		frameBufferCreateInfo.pAttachments = frameBufferAttachments.ptr;
		frameBufferCreateInfo.width = width;
		frameBufferCreateInfo.height = height;
		frameBufferCreateInfo.layers = 1;

		frameBuffers = new VkFramebuffer[](imageCount);
		foreach(index; 0 .. imageCount)
		{
			frameBufferAttachments[0] = presentImageViews[index];
			enforceVk(vkCreateFramebuffer(logicalDevice, &frameBufferCreateInfo, null, &frameBuffers[index]));
		}
	}

	void createShaderModules()
	{
		auto vertFile = File("vert.spv", "r");
		auto fragFile = File("frag.spv", "r");

		char[] vertCode = new char[](vertFile.size);
		auto vertCodeSlice = vertFile.rawRead(vertCode);

		char[] fragCode = new char[](fragFile.size);
		auto fragCodeSlice = fragFile.rawRead(fragCode);

		VkShaderModuleCreateInfo vertexShaderCreateInfo;
		vertexShaderCreateInfo.codeSize = vertCodeSlice.length;
		vertexShaderCreateInfo.pCode = cast(uint*)vertCodeSlice.ptr;

		VkShaderModuleCreateInfo fragmentShaderCreateInfo;
		fragmentShaderCreateInfo.codeSize = fragCodeSlice.length;
		fragmentShaderCreateInfo.pCode = cast(uint*)fragCodeSlice.ptr;

		enforceVk(vkCreateShaderModule(logicalDevice, &vertexShaderCreateInfo, null, &vertexShaderModule));

		enforceVk(vkCreateShaderModule(logicalDevice, &fragmentShaderCreateInfo, null, &fragmentShaderModule));
	}

	void createVertexBuffer()
	{
		VkBufferCreateInfo vertexInputBufferInfo =
		{
			size:        Vertex.sizeof * 3,
			usage:       VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
			sharingMode: VK_SHARING_MODE_EXCLUSIVE
		};

		enforceVk(vkCreateBuffer(logicalDevice, &vertexInputBufferInfo, null, &vertexInputBuffer));

		VkMemoryRequirements vertexBufferMemoryReq;
		vkGetBufferMemoryRequirements(logicalDevice, vertexInputBuffer, &vertexBufferMemoryReq);

		VkMemoryAllocateInfo bufferAllocateInfo;
		bufferAllocateInfo.allocationSize = vertexBufferMemoryReq.size;

		uint vertexMemoryTypeBits = vertexBufferMemoryReq.memoryTypeBits;
		VkMemoryPropertyFlags vertexDesiredMemoryFlags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;

		foreach(index; 0 .. 32)
		{
			VkMemoryType memoryType = memoryProperties.memoryTypes[index];
			if (vertexMemoryTypeBits & 1)
			{
				if((memoryType.propertyFlags & vertexDesiredMemoryFlags) == vertexDesiredMemoryFlags)
				{
					bufferAllocateInfo.memoryTypeIndex = index;
					break;
				}
			}
			vertexMemoryTypeBits = vertexMemoryTypeBits >> 1;
		}

		enforceVk(vkAllocateMemory(logicalDevice, &bufferAllocateInfo, null, &vertexBufferMemory));

		void* mapped;
		enforceVk(vkMapMemory(logicalDevice, vertexBufferMemory, 0, VK_WHOLE_SIZE, 0, &mapped));

		Vertex[] triangle = (cast(Vertex*)mapped)[0 .. 3];
		triangle[0] = Vertex(-1.0f, 1.0f, 0.0f, 1.0f);
		triangle[1] = Vertex(1.0f, 1.0f, 0.0f, 1.0f);
		triangle[2] = Vertex(0.0f, -1.0f, 0.0f, 1.0f);

		vkUnmapMemory(logicalDevice, vertexBufferMemory );
		enforceVk(vkBindBufferMemory(logicalDevice, vertexInputBuffer, vertexBufferMemory, 0));
	}

	void createGraphicsPipeline()
	{
		if (!pipelineLayout)
		{
			VkPipelineLayoutCreateInfo layoutCreateInfo;
			layoutCreateInfo.setLayoutCount = 0;
			layoutCreateInfo.pSetLayouts = null;        // Not setting any bindings!
			layoutCreateInfo.pushConstantRangeCount = 0;
			layoutCreateInfo.pPushConstantRanges = null;

			enforceVk(vkCreatePipelineLayout(logicalDevice, &layoutCreateInfo, null, &pipelineLayout));
		}

		VkPipelineShaderStageCreateInfo[2] shaderStageCreateInfo;
		shaderStageCreateInfo[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
		shaderStageCreateInfo[0]._module = vertexShaderModule;
		shaderStageCreateInfo[0].pName = "main";                // shader entry point function name
		shaderStageCreateInfo[0].pSpecializationInfo = null;

		shaderStageCreateInfo[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
		shaderStageCreateInfo[1]._module = fragmentShaderModule;
		shaderStageCreateInfo[1].pName = "main";                // shader entry point function name
		shaderStageCreateInfo[1].pSpecializationInfo = null;

		VkVertexInputBindingDescription vertexBindingDescription = {};
		vertexBindingDescription.binding = 0;
		vertexBindingDescription.stride = Vertex.sizeof;
		vertexBindingDescription.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;

		VkVertexInputAttributeDescription vertexAttributeDescritpion = {};
		vertexAttributeDescritpion.location = 0;
		vertexAttributeDescritpion.binding = 0;
		vertexAttributeDescritpion.format = VK_FORMAT_R32G32B32A32_SFLOAT;
		vertexAttributeDescritpion.offset = 0;

		VkPipelineVertexInputStateCreateInfo vertexInputStateCreateInfo = {};
		vertexInputStateCreateInfo.vertexBindingDescriptionCount = 1;
		vertexInputStateCreateInfo.pVertexBindingDescriptions = &vertexBindingDescription;
		vertexInputStateCreateInfo.vertexAttributeDescriptionCount = 1;
		vertexInputStateCreateInfo.pVertexAttributeDescriptions = &vertexAttributeDescritpion;

		VkPipelineInputAssemblyStateCreateInfo inputAssemblyStateCreateInfo = {};
		inputAssemblyStateCreateInfo.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
		inputAssemblyStateCreateInfo.primitiveRestartEnable = VK_FALSE;

		viewport.x = 0;
		viewport.y = 0;
		viewport.width = width;
		viewport.height = height;
		viewport.minDepth = 0;
		viewport.maxDepth = 1;

		scissors.offset = VkOffset2D( 0, 0 );
		scissors.extent = VkExtent2D( width, height );

		VkPipelineViewportStateCreateInfo viewportState;
		viewportState.viewportCount = 1;
		viewportState.pViewports = &viewport;
		viewportState.scissorCount = 1;
		viewportState.pScissors = &scissors;

		VkPipelineRasterizationStateCreateInfo rasterizationState;
		rasterizationState.depthClampEnable = VK_FALSE;
		rasterizationState.rasterizerDiscardEnable = VK_FALSE;
		rasterizationState.polygonMode = VK_POLYGON_MODE_FILL;
		rasterizationState.cullMode = VK_CULL_MODE_NONE;
		rasterizationState.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
		rasterizationState.depthBiasEnable = VK_FALSE;
		rasterizationState.depthBiasConstantFactor = 0;
		rasterizationState.depthBiasClamp = 0;
		rasterizationState.depthBiasSlopeFactor = 0;
		rasterizationState.lineWidth = 1;

		VkPipelineMultisampleStateCreateInfo multisampleState;
		multisampleState.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
		multisampleState.sampleShadingEnable = VK_FALSE;
		multisampleState.minSampleShading = 0;
		multisampleState.pSampleMask = null;
		multisampleState.alphaToCoverageEnable = VK_FALSE;
		multisampleState.alphaToOneEnable = VK_FALSE;

		VkStencilOpState noOPStencilState = {};
		noOPStencilState.failOp = VK_STENCIL_OP_KEEP;
		noOPStencilState.passOp = VK_STENCIL_OP_KEEP;
		noOPStencilState.depthFailOp = VK_STENCIL_OP_KEEP;
		noOPStencilState.compareOp = VK_COMPARE_OP_ALWAYS;
		noOPStencilState.compareMask = 0;
		noOPStencilState.writeMask = 0;
		noOPStencilState.reference = 0;

		VkPipelineDepthStencilStateCreateInfo depthState;
		depthState.depthTestEnable = VK_TRUE;
		depthState.depthWriteEnable = VK_TRUE;
		depthState.depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL;
		depthState.depthBoundsTestEnable = VK_FALSE;
		depthState.stencilTestEnable = VK_FALSE;
		depthState.front = noOPStencilState;
		depthState.back = noOPStencilState;
		depthState.minDepthBounds = 0;
		depthState.maxDepthBounds = 0;

		VkPipelineColorBlendAttachmentState colorBlendAttachmentState = {};
		colorBlendAttachmentState.blendEnable = VK_FALSE;
		colorBlendAttachmentState.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_COLOR;
		colorBlendAttachmentState.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR;
		colorBlendAttachmentState.colorBlendOp = VK_BLEND_OP_ADD;
		colorBlendAttachmentState.srcAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
		colorBlendAttachmentState.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
		colorBlendAttachmentState.alphaBlendOp = VK_BLEND_OP_ADD;
		colorBlendAttachmentState.colorWriteMask = 0xf;

		VkPipelineColorBlendStateCreateInfo colorBlendState = {};
		colorBlendState.logicOpEnable = VK_FALSE;
		colorBlendState.logicOp = VK_LOGIC_OP_CLEAR;
		colorBlendState.attachmentCount = 1;
		colorBlendState.pAttachments = &colorBlendAttachmentState;
		colorBlendState.blendConstants[0] = 0.0;
		colorBlendState.blendConstants[1] = 0.0;
		colorBlendState.blendConstants[2] = 0.0;
		colorBlendState.blendConstants[3] = 0.0;

		VkDynamicState[2] dynamicState = [ VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR ];
		VkPipelineDynamicStateCreateInfo dynamicStateCreateInfo;
		dynamicStateCreateInfo.dynamicStateCount = 2;
		dynamicStateCreateInfo.pDynamicStates = dynamicState.ptr;

		VkGraphicsPipelineCreateInfo pipelineCreateInfo = {};
		pipelineCreateInfo.stageCount = 2;
		pipelineCreateInfo.pStages = shaderStageCreateInfo.ptr;
		pipelineCreateInfo.pVertexInputState = &vertexInputStateCreateInfo;
		pipelineCreateInfo.pInputAssemblyState = &inputAssemblyStateCreateInfo;
		pipelineCreateInfo.pTessellationState = null;
		pipelineCreateInfo.pViewportState = &viewportState;
		pipelineCreateInfo.pRasterizationState = &rasterizationState;
		pipelineCreateInfo.pMultisampleState = &multisampleState;
		pipelineCreateInfo.pDepthStencilState = &depthState;
		pipelineCreateInfo.pColorBlendState = &colorBlendState;
		pipelineCreateInfo.pDynamicState = &dynamicStateCreateInfo;
		pipelineCreateInfo.layout = pipelineLayout;
		pipelineCreateInfo.renderPass = renderPass;
		pipelineCreateInfo.subpass = 0;
		pipelineCreateInfo.basePipelineHandle = null;
		pipelineCreateInfo.basePipelineIndex = 0;

		enforceVk(vkCreateGraphicsPipelines(logicalDevice, null, 1, &pipelineCreateInfo, null, &pipeline));
	}

	void render()
	{
		uint32_t nextImageIdx;
		vkAcquireNextImageKHR(
			logicalDevice, swapchain, uint64_t.max,
			presentCompleteSemaphore, null, &nextImageIdx
		);

		VkCommandBufferBeginInfo beginInfo;
		vkBeginCommandBuffer( drawCmdBuffer, &beginInfo );

		VkImageMemoryBarrier layoutToColorTrans;
		layoutToColorTrans.srcAccessMask = 0;
		layoutToColorTrans.dstAccessMask =
			VK_ACCESS_COLOR_ATTACHMENT_READ_BIT |
			VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
		layoutToColorTrans.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
		layoutToColorTrans.newLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
		layoutToColorTrans.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
		layoutToColorTrans.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
		layoutToColorTrans.image = presentImages[ nextImageIdx ];
		auto resourceRange = VkImageSubresourceRange( VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 );
		layoutToColorTrans.subresourceRange = resourceRange;

		vkCmdPipelineBarrier(
			drawCmdBuffer,
			VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
			VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
			0,
			0, null,
			0, null,
			1, &layoutToColorTrans
		);
		VkClearColorValue clearColorValue;
		clearColorValue.float32[0] = 1.0f;
		clearColorValue.float32[1] = 1.0f;
		clearColorValue.float32[2] = 1.0f;
		clearColorValue.float32[3] = 1.0f;

		VkClearValue firstclearValue;
		firstclearValue.color = clearColorValue;

		VkClearValue secondclearValue;
		secondclearValue.depthStencil = VkClearDepthStencilValue(1.0, 0);

		VkClearValue[2] clearValue = [ firstclearValue, secondclearValue ];

		VkRenderPassBeginInfo renderPassBeginInfo;
		renderPassBeginInfo.renderPass = renderPass;
		renderPassBeginInfo.framebuffer = frameBuffers[ nextImageIdx ];
		renderPassBeginInfo.renderArea = VkRect2D(VkOffset2D(0, 0), VkExtent2D(width, height));
		renderPassBeginInfo.clearValueCount = 2;
		renderPassBeginInfo.pClearValues = clearValue.ptr;

		vkCmdBeginRenderPass(
			drawCmdBuffer, &renderPassBeginInfo,
			VK_SUBPASS_CONTENTS_INLINE
		);

		vkCmdBindPipeline(drawCmdBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
		vkCmdSetViewport(drawCmdBuffer, 0, 1, &viewport);
		vkCmdSetScissor(drawCmdBuffer, 0 ,1, &scissors);

		VkDeviceSize offsets;
		vkCmdBindVertexBuffers( drawCmdBuffer, 0, 1, &vertexInputBuffer, &offsets );
		vkCmdDraw( drawCmdBuffer, 3, 1, 0, 0 );
		vkCmdEndRenderPass( drawCmdBuffer );

		VkImageMemoryBarrier prePresentBarrier;
		prePresentBarrier.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
		prePresentBarrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT;
		prePresentBarrier.oldLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
		prePresentBarrier.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
		prePresentBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
		prePresentBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
		prePresentBarrier.subresourceRange = resourceRange;
		prePresentBarrier.image = presentImages[ nextImageIdx ];

		vkCmdPipelineBarrier(
			drawCmdBuffer,
			VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
			VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
			0,
			0, null,
			0, null,
			1, &prePresentBarrier
		);

		vkEndCommandBuffer( drawCmdBuffer );

		VkPipelineStageFlags[1] waitRenderMask = [ VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT ];
		VkSubmitInfo renderSubmitInfo;
		renderSubmitInfo.waitSemaphoreCount = 1;
		renderSubmitInfo.pWaitSemaphores = &presentCompleteSemaphore;
		renderSubmitInfo.pWaitDstStageMask = waitRenderMask.ptr;
		renderSubmitInfo.commandBufferCount = 1;
		renderSubmitInfo.pCommandBuffers = &drawCmdBuffer;
		renderSubmitInfo.signalSemaphoreCount = 1;
		renderSubmitInfo.pSignalSemaphores = &renderingCompleteSemaphore;
		vkQueueSubmit( presentQueue, 1, &renderSubmitInfo, null );
		vkQueueWaitIdle(presentQueue);

		VkPresentInfoKHR presentInfo;
		presentInfo.pNext = null;
		presentInfo.waitSemaphoreCount = 1;
		presentInfo.pWaitSemaphores = &renderingCompleteSemaphore;
		presentInfo.swapchainCount = 1;
		presentInfo.pSwapchains = &swapchain;
		presentInfo.pImageIndices = &nextImageIdx;
		presentInfo.pResults = null;
		vkQueuePresentKHR( presentQueue, &presentInfo );
		vkQueueWaitIdle(presentQueue);
	}

	void resize()
	{
		alias device = logicalDevice;
		vkDeviceWaitIdle(device);

		/***********************/
		/*       pipeline      */
		/***********************/
		assert(pipeline);
		vkDestroyPipeline(device, pipeline, null);
		pipeline = null;

		/***********************/
		/*     framebuffers    */
		/***********************/
		foreach(framebuffer; frameBuffers)
		{
			assert(framebuffer);
			vkDestroyFramebuffer(device, framebuffer, null);
		}
		frameBuffers.length = 0;

		// do we have to do that?
		assert(renderPass);
		vkDestroyRenderPass(device, renderPass, null);
		renderPass = null;

		vkDestroyImageView(logicalDevice, depthImageView, null);
		vkDestroyImage(logicalDevice, depthImage, null);
		vkFreeMemory(logicalDevice, imageMemory, null);
		depthImageView = null;
		depthImage = null;
		imageMemory = null;

		foreach(imageView; presentImageViews)
			vkDestroyImageView(device, imageView, null);
		presentImageViews.length = 0;

		/***********************/
		/*      swapchain      */
		/***********************/
		assert(swapchain);
		vkDestroySwapchainKHR(device, swapchain, null);
		swapchain = null;

		/***********************/
		/*      recreate       */
		/***********************/
		createSwapchain();
		createFramebuffers();
		createGraphicsPipeline();
	}

	void eventLoop()
	{
		auto semaphoreCreateInfo = VkSemaphoreCreateInfo( VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO, null, 0 );
		vkCreateSemaphore( logicalDevice, &semaphoreCreateInfo, null, &presentCompleteSemaphore );
		vkCreateSemaphore( logicalDevice, &semaphoreCreateInfo, null, &renderingCompleteSemaphore );

		bool shouldClose = false;
		while(!shouldClose)
		{
			int oldWidth = width;
			int oldHeight = height;
			SDL_Event event;
			while(SDL_PollEvent(&event)){
				PrintEvent(&event);
				switch (event.type)
				{
					case SDL_WINDOWEVENT:
					{
						switch (event.window.event)
						{
							case SDL_WINDOWEVENT_SIZE_CHANGED:
							{
								width = event.window.data1;
								height = event.window.data2;
								SDL_Log("resized");
								break;
							}
							default:
						}
						break;
					}
					case SDL_QUIT:
						shouldClose = true;
						break;
					default:
				}
			}

			if (width != oldWidth || height != oldHeight)
				resize();
			render();
		}
	}

	static if (false) void clear()
	{
		if (device != VK_NULL_HANDLE)
		{
			vkDeviceWaitIdle(device);

			if (graphicsCommandBuffers.length > 0 &&
				graphicsCommandBuffers[0] != VK_NULL_HANDLE)
			{
				vkFreeCommandBuffers(device,
						graphicsCommandPool,
						cast(uint32_t) graphicsCommandBuffers.length,
						graphicsCommandBuffers.ptr);
				graphicsCommandBuffers.length = 0;
			}

			if (graphicsCommandPool != VK_NULL_HANDLE)
			{
				vkDestroyCommandPool(device, graphicsCommandPool, null);
				graphicsCommandPool = VK_NULL_HANDLE;
			}

			if (graphicsPipeline != VK_NULL_HANDLE)
			{
				vkDestroyPipeline(device, graphicsPipeline, null);
				graphicsPipeline = VK_NULL_HANDLE;
			}

			if (renderPass != VK_NULL_HANDLE)
			{
				vkDestroyRenderPass(device, renderPass, null);
				renderPass = VK_NULL_HANDLE;
			}

			foreach(ref framebuffer; framebuffers)
			{
				if (framebuffer != VK_NULL_HANDLE)
				{
					vkDestroyFramebuffer(device, framebuffer, null);
					framebuffer = VK_NULL_HANDLE;
				}
			}
			framebuffers.length = 0;

			foreach(image; swapchain.images)
				if (image.imageView != VK_NULL_HANDLE)
					vkDestroyImageView(device, image.imageView, null);
			swapchain.images.length = 0;

			if (swapchain.handle != VK_NULL_HANDLE)
			{
				vkDestroySwapchainKHR(device, swapchain.handle, null);
				swapchain.handle = VK_NULL_HANDLE;
			}
		}

		/+
		if (presentationSurface)
		{
			vkDestroySurfaceKHR(instance, presentationSurface, null);
			presentationSurface = VK_NULL_HANDLE;
		}
		+/
	}
	void cleanup()
	{
		if (logicalDevice)
		{
			vkDestroyFence(logicalDevice, submitFence, null);

			vkFreeMemory(logicalDevice, vertexBufferMemory, null);
			vkDestroyBuffer(logicalDevice, vertexInputBuffer, null);
			vkDestroyPipeline(logicalDevice, pipeline, null);
			vkDestroyPipelineLayout(logicalDevice, pipelineLayout, null);
			vkDestroyRenderPass(logicalDevice, renderPass, null);

			foreach(ref framebuffer; frameBuffers)
				vkDestroyFramebuffer(logicalDevice, framebuffer, null);

			vkDestroyShaderModule(logicalDevice, fragmentShaderModule, null);
			vkDestroyShaderModule(logicalDevice, vertexShaderModule, null);

			vkDestroyImageView(logicalDevice, depthImageView, null);
			vkDestroyImage(logicalDevice, depthImage, null);
			vkFreeMemory(logicalDevice, imageMemory, null);

			vkFreeCommandBuffers(logicalDevice, commandPool, 1, &drawCmdBuffer);
			vkFreeCommandBuffers(logicalDevice, commandPool, 1, &setupCmdBuffer);
			vkDestroyCommandPool(logicalDevice, commandPool, null);

			foreach(ref presentImageView; presentImageViews)
				vkDestroyImageView(logicalDevice, presentImageView, null);

			vkDestroySwapchainKHR(logicalDevice, swapchain, null);

			vkDestroySemaphore(logicalDevice, presentCompleteSemaphore, null);
			vkDestroySemaphore(logicalDevice, renderingCompleteSemaphore, null);

			vkDestroyDevice(logicalDevice, null);
		}

		if (instance)
		{
			vkDestroySurfaceKHR(instance, surface, null);
			vkDestroyDebugReportCallbackEXT(instance, callback, null);
			vkDestroyInstance(instance, null);
		}
	}
}

void main()
{
    VkContext vulkan;
    vulkan.width = 800;
    vulkan.height = 600;

    DerelictSDL2.load();
    auto sdlWindow = SDL_CreateWindow("vulkan", 0, 0, 800, 600, SDL_WINDOW_RESIZABLE);
    SDL_SysWMinfo sdlWindowInfo;

    SDL_VERSION(&sdlWindowInfo.version_);
    enforce(SDL_GetWindowWMInfo(sdlWindow, &sdlWindowInfo), "sdl err");

    DerelictErupted.load();

	vulkan.createInstance();
	vulkan.createDebugReportCallback();
	vulkan.createSurface(sdlWindowInfo);
	vulkan.createDevice();
	vulkan.createVertexBuffer();
	vulkan.createShaderModules();
	vulkan.createCommandPool();
	vulkan.allocateCommandBuffers();

	vulkan.createSwapchain();
	vulkan.createFramebuffers();
	vulkan.createGraphicsPipeline();

	vulkan.eventLoop();
	vulkan.cleanup();
}
