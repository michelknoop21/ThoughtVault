#!/usr/bin/env python3
"""Generate DMG background image with drag-to-install arrow.

Uses CoreGraphics via ctypes — no pip dependencies, works with any macOS Python.
Output: dmg-background.png (660x400) in the same directory as this script.
"""
import ctypes
import ctypes.util
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT = os.path.join(SCRIPT_DIR, "dmg-background.png")

WIDTH, HEIGHT = 660, 400

# Load frameworks
cg = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreGraphics"))
cf = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreFoundation"))
imageio = ctypes.cdll.LoadLibrary(ctypes.util.find_library("ImageIO"))

# Type definitions
CGFloat = ctypes.c_double

class CGPoint(ctypes.Structure):
    _fields_ = [("x", CGFloat), ("y", CGFloat)]

class CGSize(ctypes.Structure):
    _fields_ = [("width", CGFloat), ("height", CGFloat)]

class CGRect(ctypes.Structure):
    _fields_ = [("origin", CGPoint), ("size", CGSize)]

# Function signatures
cg.CGColorSpaceCreateDeviceRGB.restype = ctypes.c_void_p
cg.CGBitmapContextCreate.restype = ctypes.c_void_p
cg.CGBitmapContextCreate.argtypes = [
    ctypes.c_void_p, ctypes.c_size_t, ctypes.c_size_t,
    ctypes.c_size_t, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_uint32
]
cg.CGContextSetRGBFillColor.argtypes = [ctypes.c_void_p, CGFloat, CGFloat, CGFloat, CGFloat]
cg.CGContextFillRect.argtypes = [ctypes.c_void_p, CGRect]
cg.CGContextSetRGBStrokeColor.argtypes = [ctypes.c_void_p, CGFloat, CGFloat, CGFloat, CGFloat]
cg.CGContextSetLineWidth.argtypes = [ctypes.c_void_p, CGFloat]
cg.CGContextSetLineCap.argtypes = [ctypes.c_void_p, ctypes.c_int32]
cg.CGContextSetLineJoin.argtypes = [ctypes.c_void_p, ctypes.c_int32]
cg.CGContextSetLineDash.argtypes = [ctypes.c_void_p, CGFloat, ctypes.POINTER(CGFloat), ctypes.c_size_t]
cg.CGContextMoveToPoint.argtypes = [ctypes.c_void_p, CGFloat, CGFloat]
cg.CGContextAddLineToPoint.argtypes = [ctypes.c_void_p, CGFloat, CGFloat]
cg.CGContextStrokePath.argtypes = [ctypes.c_void_p]
cg.CGContextSelectFont.argtypes = [ctypes.c_void_p, ctypes.c_char_p, CGFloat, ctypes.c_int32]
cg.CGContextSetTextDrawingMode.argtypes = [ctypes.c_void_p, ctypes.c_int32]
cg.CGContextShowTextAtPoint.argtypes = [ctypes.c_void_p, CGFloat, CGFloat, ctypes.c_char_p, ctypes.c_size_t]
cg.CGBitmapContextCreateImage.restype = ctypes.c_void_p
cg.CGBitmapContextCreateImage.argtypes = [ctypes.c_void_p]
cg.CGContextRelease.argtypes = [ctypes.c_void_p]
cg.CGImageRelease.argtypes = [ctypes.c_void_p]
cg.CGColorSpaceRelease.argtypes = [ctypes.c_void_p]

cf.CFURLCreateFromFileSystemRepresentation.restype = ctypes.c_void_p
cf.CFURLCreateFromFileSystemRepresentation.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_bool]
cf.CFRelease.argtypes = [ctypes.c_void_p]

imageio.CGImageDestinationCreateWithURL.restype = ctypes.c_void_p
imageio.CGImageDestinationCreateWithURL.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p]
imageio.CGImageDestinationAddImage.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
imageio.CGImageDestinationFinalize.argtypes = [ctypes.c_void_p]
imageio.CGImageDestinationFinalize.restype = ctypes.c_bool

# CFString for "public.png"
cf.CFStringCreateWithCString.restype = ctypes.c_void_p
cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
kCFStringEncodingUTF8 = 0x08000100
png_uti = cf.CFStringCreateWithCString(None, b"public.png", kCFStringEncodingUTF8)

# Constants
kCGImageAlphaPremultipliedLast = 1
kCGLineCapRound = 1
kCGLineJoinRound = 1
kCGTextFill = 0
kCGEncodingMacRoman = 0

# Create color space and context
color_space = cg.CGColorSpaceCreateDeviceRGB()
ctx = cg.CGBitmapContextCreate(
    None, WIDTH, HEIGHT, 8, WIDTH * 4, color_space, kCGImageAlphaPremultipliedLast
)

# --- Background ---
# Clean light background for readable icon labels
cg.CGContextSetRGBFillColor(ctx, 0.949, 0.949, 0.969, 1.0)  # #F2F2F7 (system grouped bg)
cg.CGContextFillRect(ctx, CGRect(CGPoint(0, 0), CGSize(WIDTH, HEIGHT)))

# --- Dashed arrow line ---
# App icon at x≈165, Applications at x≈495, both at y≈200 (from top)
arrow_y = CGFloat(HEIGHT - 200)  # CG y-axis is flipped

cg.CGContextSetRGBStrokeColor(ctx, 0.0, 0.0, 0.0, 0.20)
cg.CGContextSetLineWidth(ctx, CGFloat(2.5))
cg.CGContextSetLineCap(ctx, kCGLineCapRound)

# Set dash pattern
dash = (CGFloat * 2)(8.0, 6.0)
cg.CGContextSetLineDash(ctx, CGFloat(0), dash, 2)

cg.CGContextMoveToPoint(ctx, CGFloat(248), arrow_y)
cg.CGContextAddLineToPoint(ctx, CGFloat(388), arrow_y)
cg.CGContextStrokePath(ctx)

# --- Arrow head (solid) ---
cg.CGContextSetLineDash(ctx, CGFloat(0), None, 0)
cg.CGContextSetRGBStrokeColor(ctx, 0.0, 0.0, 0.0, 0.30)
cg.CGContextSetLineWidth(ctx, CGFloat(2.5))
cg.CGContextSetLineJoin(ctx, kCGLineJoinRound)
cg.CGContextSetLineCap(ctx, kCGLineCapRound)

cg.CGContextMoveToPoint(ctx, CGFloat(378), CGFloat(arrow_y.value + 13))
cg.CGContextAddLineToPoint(ctx, CGFloat(397), arrow_y)
cg.CGContextAddLineToPoint(ctx, CGFloat(378), CGFloat(arrow_y.value - 13))
cg.CGContextStrokePath(ctx)

# --- Instruction text (using CoreText for proper Unicode) ---
ct = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreText"))

ct.CTFontCreateWithName.restype = ctypes.c_void_p
ct.CTFontCreateWithName.argtypes = [ctypes.c_void_p, CGFloat, ctypes.c_void_p]
ct.CTLineCreateWithAttributedString.restype = ctypes.c_void_p
ct.CTLineCreateWithAttributedString.argtypes = [ctypes.c_void_p]
ct.CTLineDraw.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
ct.CTLineGetTypographicBounds.restype = ctypes.c_double
ct.CTLineGetTypographicBounds.argtypes = [ctypes.c_void_p, ctypes.POINTER(CGFloat), ctypes.POINTER(CGFloat), ctypes.POINTER(CGFloat)]

cf.CFAttributedStringCreate.restype = ctypes.c_void_p
cf.CFAttributedStringCreate.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
cf.CFDictionaryCreate.restype = ctypes.c_void_p
cf.CFDictionaryCreate.argtypes = [
    ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_void_p),
    ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p
]

# Create font
font_name = cf.CFStringCreateWithCString(None, b"Helvetica Neue", kCFStringEncodingUTF8)
font = ct.CTFontCreateWithName(font_name, CGFloat(13.0), None)

# Create color
cg.CGColorCreate.restype = ctypes.c_void_p
cg.CGColorCreate.argtypes = [ctypes.c_void_p, ctypes.POINTER(CGFloat)]
color_components = (CGFloat * 4)(0.0, 0.0, 0.0, 0.40)
text_color = cg.CGColorCreate(color_space, color_components)

# Attribute keys
kCTFontAttributeName = ctypes.c_void_p.in_dll(ct, "kCTFontAttributeName")
kCTForegroundColorAttributeName = ctypes.c_void_p.in_dll(ct, "kCTForegroundColorAttributeName")

keys = (ctypes.c_void_p * 2)(kCTFontAttributeName, kCTForegroundColorAttributeName)
vals = (ctypes.c_void_p * 2)(font, text_color)
attrs = cf.CFDictionaryCreate(None, keys, vals, 2, None, None)

# Create attributed string
text_str = cf.CFStringCreateWithCString(None, "Sleep naar Programma\u2019s om te installeren".encode("utf-8"), kCFStringEncodingUTF8)
attr_str = cf.CFAttributedStringCreate(None, text_str, attrs)

# Create CTLine and measure
line = ct.CTLineCreateWithAttributedString(attr_str)
ascent, descent, leading = CGFloat(), CGFloat(), CGFloat()
line_width = ct.CTLineGetTypographicBounds(line, ctypes.byref(ascent), ctypes.byref(descent), ctypes.byref(leading))

# Draw centered text
text_x = (WIDTH - line_width) / 2
text_y = HEIGHT - 345
cg.CGContextSetTextPosition.argtypes = [ctypes.c_void_p, CGFloat, CGFloat]
cg.CGContextSetTextPosition(ctx, CGFloat(text_x), CGFloat(text_y))
ct.CTLineDraw(line, ctx)

# Cleanup text objects
cf.CFRelease(line)
cf.CFRelease(attr_str)
cf.CFRelease(attrs)
cf.CFRelease(text_str)
cf.CFRelease(font_name)
cf.CFRelease(font)

# --- Save as PNG ---
image = cg.CGBitmapContextCreateImage(ctx)

output_bytes = OUTPUT.encode("utf-8")
url = cf.CFURLCreateFromFileSystemRepresentation(None, output_bytes, len(output_bytes), False)

dest = imageio.CGImageDestinationCreateWithURL(url, png_uti, 1, None)
imageio.CGImageDestinationAddImage(dest, image, None)
result = imageio.CGImageDestinationFinalize(dest)

# Cleanup
cf.CFRelease(dest)
cf.CFRelease(url)
cg.CGImageRelease(image)
cg.CGContextRelease(ctx)
cg.CGColorSpaceRelease(color_space)
cf.CFRelease(png_uti)

if result:
    size = os.path.getsize(OUTPUT)
    print(f"Generated: {OUTPUT} ({size:,} bytes)")
else:
    print("ERROR: Failed to write PNG")
    exit(1)
