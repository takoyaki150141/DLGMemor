TARGET := iphone:clang:latest:16.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = DLGMemor

DLGMemor_FILES = \
    DLGMemor/mem/mem.c \
    DLGMemor/mem/mem_utils.c \
    DLGMemor/mem/search_result.c \
    DLGMemor/memui/DLGMem.m \
    DLGMemor/memui/DLGMemEntry.m \
    DLGMemor/memui/category/UIWindow+DLGMemUI.m \
    DLGMemor/memui/views/DLGMemUI.m \
    DLGMemor/memui/views/DLGMemUIView.m \
    DLGMemor/memui/views/DLGMemUIViewCell.m

DLGMemor_CFLAGS = -fobjc-arc
DLGMemor_OBJCFLAGS = -fobjc-arc -Wno-deprecated-declarations
DLGMemor_LDFLAGS = -Wl,-segalign,4000
DLGMemor_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/library.mk