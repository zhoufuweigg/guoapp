#import "DuanjuCoreAnchor.h"
#include <stddef.h>

extern char *DuanjuRequest(char *input);
extern void DuanjuFree(char *value);

void DjuEnsureCoreLinked(void) {
    char *result = DuanjuRequest(NULL);
    if (result != NULL) {
        DuanjuFree(result);
    }
}
