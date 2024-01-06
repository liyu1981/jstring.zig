#include "pcre_binding.h"

#include <stdio.h>
#include <string.h>

#define PCRE2_CODE_UNIT_WIDTH 8
#include "pcre2.h"

#define TRUE 1
#define FALSE 0

// reference: https://pcre2project.github.io/pcre2/doc/html/pcre2demo.html

void get_last_error_message(RegexContext* context) {
    PCRE2_UCHAR buffer[256];
    pcre2_get_error_message(context->error_number, buffer, sizeof(buffer));
    context->error_message_len = sprintf(context->error_message,
                                         "PCRE2 compilation failed at offset %d: %s\n",
                                         (int)context->error_offset,
                                         buffer);
}

void reset_context(RegexContext* context) {
    context->error_number = 0;
    context->error_offset = 0;
    context->error_message_len = 0;

    context->with_match_result = FALSE;
    context->named_group_count = 0;
    context->next_offset = 0;
    context->origin_offset = 0;
    context->rc = 0;

    context->matched_count = 0;
    context->matched_results_capacity = 0;
    context->matched_results = NULL;

    context->matched_group_count = 0;
    context->matched_group_results = NULL;

    context->match_data = NULL;
    context->re = NULL;
}

uint8_t compile(RegexContext* context, const unsigned char* pattern) {
    reset_context(context);

    pcre2_code* re = pcre2_compile(
        pattern,
        PCRE2_ZERO_TERMINATED,
        0,
        &context->error_number,
        &context->error_offset,
        NULL);
    context->re = (void*)re;

    if (re != NULL) {
        pcre2_pattern_info(re, PCRE2_INFO_NAMECOUNT, &context->named_group_count);
    }

    return re == NULL ? FALSE : TRUE;
}

void free_context(RegexContext* context) {
    if (context->re != NULL) {
        pcre2_code_free((pcre2_code*)context->re);
    }
    if (context->match_data != NULL) {
        pcre2_match_data_free((pcre2_match_data*)context->match_data);
    }
    reset_context(context);
}

int64_t match(RegexContext* context, const unsigned char* subject, size_t subject_len, size_t start_offset) {
    if (context->re == NULL) {
        return 0;
    }

    context->match_data = pcre2_match_data_create_from_pattern(context->re, NULL);
    context->rc = pcre2_match(
        (pcre2_code*)context->re,
        subject,
        subject_len,
        start_offset,
        context->match_options,
        context->match_data,
        NULL);
    context->matched_results_capacity = context->rc;
    context->with_match_result = TRUE;
    context->origin_offset = start_offset;

    return context->rc;
}

void prepare_named_groups(RegexContext* context) {
    if (context->re != NULL && context->named_group_count > 0) {
        PCRE2_SPTR name_table;
        uint32_t name_entry_size;
        PCRE2_SPTR tabptr;
        int n;
        int i;

        pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_NAMETABLE, &name_table);
        pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_NAMEENTRYSIZE, &name_entry_size);
        tabptr = name_table;

        for (i = 0; i < context->named_group_count; i++) {
            n = (tabptr[0] << 8) | tabptr[1];
            (context->matched_group_results + i)->name_len = name_entry_size - 3;
            tabptr += name_entry_size;
        }
    }
}

void fetch_match_results(RegexContext* context) {
    if (context->with_match_result == FALSE) {
        return;
    }

    int i;
    int j;
    int n;
    PCRE2_SPTR name_table;
    uint32_t name_entry_size;
    PCRE2_SPTR tabptr;
    PCRE2_SIZE* ovector = pcre2_get_ovector_pointer(context->match_data);

    pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_NAMETABLE, &name_table);
    pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_NAMEENTRYSIZE, &name_entry_size);

    if (context->named_group_count > 0) {
        tabptr = name_table;
        for (i = 0; i < context->named_group_count; i++) {
            n = (tabptr[0] << 8) | tabptr[1];
            sprintf((context->matched_group_results + i)->name, "%.*s", name_entry_size - 3, tabptr + 2);
            (context->matched_group_results + i)->start = ovector[2 * n];
            (context->matched_group_results + i)->len = ovector[2 * n + 1] - ovector[2 * n];
            tabptr += name_entry_size;
        }

        // after each single match, set this to match named_group_count
        // if multiple matches, matched_group_count will be reassign to the total matched_group_count
        context->matched_group_count = context->named_group_count;
    }

    tabptr = name_table;
    for (i = 0, j = 0; i < context->rc; i++) {
        n = (tabptr[0] << 8) | tabptr[1];
        if (i == n) {
            // this is a group result, skip and move to next entry
            tabptr += name_entry_size;
            continue;
        } else {
            (context->matched_results + j)->start = ovector[2 * i];
            (context->matched_results + j)->len = ovector[2 * i + 1] - ovector[2 * i];
            j++;
        }
    }
    context->matched_count = j;
}

void get_next_offset(RegexContext* context, const unsigned char* subject, size_t subject_len) {
    if (context->with_match_result == FALSE) {
        return;
    }

    uint32_t option_bits;
    pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_ALLOPTIONS, &option_bits);

    int utf8 = (option_bits & PCRE2_UTF) != 0;

    PCRE2_SIZE* ovector = (PCRE2_SIZE*)pcre2_get_ovector_pointer(context->match_data);
    PCRE2_SIZE start_offset = ovector[1];

    if (ovector[0] != ovector[1]) {
        // as instructed by pcre2 demo code to handle tricky case to avoid infinite loop
        PCRE2_SIZE startchar = pcre2_get_startchar(context->match_data);
        if (start_offset <= startchar) {
            if (startchar >= subject_len) {
                start_offset = subject_len; /* Reached end of subject.   */
            }
            start_offset = startchar + 1; /* Advance by one character. */
            if (utf8) {                   /* If UTF-8, it may be more than one code unit. */
                for (; start_offset < subject_len; start_offset++)
                    if ((subject[start_offset] & 0xc0) != 0x80) break;
            }
        }
    }

    context->next_offset = start_offset;
}

void free_for_next_match(RegexContext* context) {
    if (context->with_match_result == FALSE) {
        return;
    }

    if (context->re != NULL) {
        pcre2_code_free((pcre2_code*)context->re);
    }
    if (context->match_data != NULL) {
        pcre2_match_data_free((pcre2_match_data*)context->match_data);
    }

    context->error_number = 0;
    context->error_offset = 0;
    context->error_message_len = 0;

    context->with_match_result = FALSE;
    // context->named_group_count = 0;
    context->next_offset = 0;
    context->origin_offset = 0;
    context->rc = 0;

    context->matched_count = 0;
    context->matched_results = NULL;

    context->matched_group_count = 0;
    context->matched_group_results = NULL;

    context->match_data = NULL;
    // context->re = NULL;
}
