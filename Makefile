TARGET := iphone:clang:latest:16.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = DLGMemor

# Source tree lives 4 levels deep (DLGMemor/DLGMemor/DLGMemor/DLGMemor/<...>)
# because the original Xcode project was nested that way and the public
# headers reference each other with just their filename.
DLGMemor_FILES = \
    DLGMemor/DLGMemor/DLGMemor/mem/mem.c \
    DLGMemor/DLGMemor/DLGMemor/mem/mem_utils.c \
    DLGMemor/DLGMemor/DLGMemor/mem/search_result.c \
    DLGMemor/DLGMemor/DLGMemor/memui/DLGMem.m \
    DLGMemor/DLGMemor/DLGMemor/memui/DLGMemEntry.m \
    DLGMemor/DLGMemor/DLGMemor/memui/category/UIWindow+DLGMemUI.m \
    DLGMemor/DLGMemor/DLGMemor/memui/views/DLGMemUI.m \
    DLGMemor/DLGMemor/DLGMemor/memui/views/DLGMemUIView.m \
    DLGMemor/DLGMemor/DLGMemor/memui/views/DLGMemUIViewCell.m

DLGMemor_CFLAGS = -fobjc-arc \
    -I$(PWD)/DLGMemor/DLGMemor/DLGMemor/memui \
    -I$(PWD)/DLGMemor/DLGMemor/DLGMemor/memui/views \
    -I$(PWD)/DLGMemor/DLGMemor/DLGMemor/memui/category \
    -I$(PWD)/DLGMemor/DLGMemor/DLGMemor/mem
DLGMemor_OBJCFLAGS = -fobjc-arc -Wno-deprecated-declarations
DLGMemor_LDFLAGS = -Wl,-segalign,4000
DLGMemor_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/library.mk