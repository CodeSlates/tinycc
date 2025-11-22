#ifndef _STDBOOL_H
#define _STDBOOL_H


#ifdef __cplusplus

/* C++ already has a native bool */
#define _Bool bool
#define bool bool
#define true true
#define false false
#define __bool_true_false_are_defined 1

#else /* __cplusplus */

#ifndef __bool_true_false_are_defined

#if !defined(__STDC_VERSION__) || (__STDC_VERSION__ < 199901L)
typedef unsigned char _Bool;
#endif

#define bool _Bool
#define true 1
#define false 0
#define __bool_true_false_are_defined 1

#endif /* __bool_true_false_are_defined */

#endif /* __cplusplus */

#endif /* _STDBOOL_H */
