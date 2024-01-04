#ifndef __PCRE_BINDING_H__
#define __PCRE_BINDING_H__

#include <stddef.h>
#include <stdint.h>

// following options are copied from pcre2.h

/* The following option bits can be passed to pcre2_compile(), pcre2_match(),
or pcre2_dfa_match(). PCRE2_NO_UTF_CHECK affects only the function to which it
is passed. Put these bits at the most significant end of the options word so
others can be added next to them */

#define PCRE2_ANCHORED 0x80000000u
#define PCRE2_NO_UTF_CHECK 0x40000000u
#define PCRE2_ENDANCHORED 0x20000000u

/* The following option bits can be passed only to pcre2_compile(). However,
they may affect compilation, JIT compilation, and/or interpretive execution.
The following tags indicate which:

C   alters what is compiled by pcre2_compile()
J   alters what is compiled by pcre2_jit_compile()
M   is inspected during pcre2_match() execution
D   is inspected during pcre2_dfa_match() execution
*/

#define PCRE2_ALLOW_EMPTY_CLASS 0x00000001u   /* C       */
#define PCRE2_ALT_BSUX 0x00000002u            /* C       */
#define PCRE2_AUTO_CALLOUT 0x00000004u        /* C       */
#define PCRE2_CASELESS 0x00000008u            /* C       */
#define PCRE2_DOLLAR_ENDONLY 0x00000010u      /*   J M D */
#define PCRE2_DOTALL 0x00000020u              /* C       */
#define PCRE2_DUPNAMES 0x00000040u            /* C       */
#define PCRE2_EXTENDED 0x00000080u            /* C       */
#define PCRE2_FIRSTLINE 0x00000100u           /*   J M D */
#define PCRE2_MATCH_UNSET_BACKREF 0x00000200u /* C J M   */
#define PCRE2_MULTILINE 0x00000400u           /* C       */
#define PCRE2_NEVER_UCP 0x00000800u           /* C       */
#define PCRE2_NEVER_UTF 0x00001000u           /* C       */
#define PCRE2_NO_AUTO_CAPTURE 0x00002000u     /* C       */
#define PCRE2_NO_AUTO_POSSESS 0x00004000u     /* C       */
#define PCRE2_NO_DOTSTAR_ANCHOR 0x00008000u   /* C       */
#define PCRE2_NO_START_OPTIMIZE 0x00010000u   /*   J M D */
#define PCRE2_UCP 0x00020000u                 /* C J M D */
#define PCRE2_UNGREEDY 0x00040000u            /* C       */
#define PCRE2_UTF 0x00080000u                 /* C J M D */
#define PCRE2_NEVER_BACKSLASH_C 0x00100000u   /* C       */
#define PCRE2_ALT_CIRCUMFLEX 0x00200000u      /*   J M D */
#define PCRE2_ALT_VERBNAMES 0x00400000u       /* C       */
#define PCRE2_USE_OFFSET_LIMIT 0x00800000u    /*   J M D */
#define PCRE2_EXTENDED_MORE 0x01000000u       /* C       */
#define PCRE2_LITERAL 0x02000000u             /* C       */
#define PCRE2_MATCH_INVALID_UTF 0x04000000u   /*   J M D */

typedef struct {
    size_t start;
    size_t len;
} RegexMatchResult;

typedef struct {
    char* name;
    size_t name_len;
    size_t start;
    size_t len;
} RegexNamedGroupResult;

typedef struct {
    int error_number;
    size_t error_offset;
    char error_message[512];
    size_t error_message_len;

    uint32_t regex_options;
    uint32_t match_options;

    uint8_t with_match_result;
    uint32_t named_group_count;
    size_t next_offset;
    size_t origin_offset;
    int64_t rc;

    int64_t matched_count;
    int64_t matched_results_capacity;
    RegexMatchResult* matched_results;

    int64_t matched_group_count;
    RegexNamedGroupResult* matched_group_results;

    void* re;
    void* match_data;
} RegexContext;

void get_last_error_message(RegexContext* context);
uint8_t compile(RegexContext* context, const unsigned char* pattern);
void free_context(RegexContext* context);
int64_t match(RegexContext* context, const unsigned char* subject, size_t subject_len, size_t start_offset);
void prepare_named_groups(RegexContext* context);
void fetch_match_results(RegexContext* context);
void get_next_offset(RegexContext* context, const unsigned char* subject, size_t subject_len);
void free_for_next_match(RegexContext* context);

#endif
