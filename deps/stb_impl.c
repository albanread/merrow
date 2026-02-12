#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

/*
 * Set fast defaults: compression level 1 (minimal deflate, enabled by
 * our patch removing the quality<5 clamp) and filter 0 (no PNG row
 * filtering).  This gives a good speed/size trade-off for diagram
 * rendering.
 *
 * Called automatically before main() via constructor attribute.
 */
__attribute__((constructor))
static void stbi_fast_png_defaults(void) {
    stbi_write_png_compression_level = 1;
    stbi_write_force_png_filter = 0;
}