#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef uint16_t WCHAR;

extern void add_load_order_override(const WCHAR *entry);
extern void prepend_dll_path(const char *path);

static int string_ends_with(const char *value, const char *suffix)
{
    size_t value_length;
    size_t suffix_length;

    if (!value || !suffix) return 0;

    value_length = strlen(value);
    suffix_length = strlen(suffix);
    if (value_length < suffix_length) return 0;

    return !strcmp(value + value_length - suffix_length, suffix);
}

static char *derive_gptk_wine_root(void)
{
    static const char suffix[] = "/external/libd3dshared.dylib";
    static const char wine_suffix[] = "/wine";
    const char *libd3dshared = getenv("CX_APPLEGPTK_LIBD3DSHARED_PATH");
    size_t prefix_length;
    char *wine_root;

    if (!string_ends_with(libd3dshared, suffix)) return NULL;

    prefix_length = strlen(libd3dshared) - strlen(suffix);
    wine_root = malloc(prefix_length + sizeof(wine_suffix));
    if (!wine_root) return NULL;

    memcpy(wine_root, libd3dshared, prefix_length);
    memcpy(wine_root + prefix_length, wine_suffix, sizeof(wine_suffix));
    return wine_root;
}

__attribute__((constructor))
static void konyak_cxcompatdb_init(void)
{
    static const WCHAR gptk_d3dmetal_override[] = {
        'd','x','g','i',',',
        'd','3','d','1','1',',',
        'd','3','d','1','2',',',
        'n','v','a','p','i','6','4',',',
        'n','v','n','g','x','=',
        'n',',','b',0
    };
    char *gptk_wine_root = derive_gptk_wine_root();

    if (!gptk_wine_root) return;

    add_load_order_override(gptk_d3dmetal_override);
    setenv("CX_ACTIVE_GRAPHICS_BACKEND", "d3dmetal", 1);
    prepend_dll_path(gptk_wine_root);

    /*
     * prepend_dll_path stores the pointer directly instead of copying it.
     * Keep gptk_wine_root allocated for the lifetime of the process.
     */
}
