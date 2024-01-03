#include "pcre_binding.h"

#include <stdio.h>
#include <string.h>

#define PCRE2_CODE_UNIT_WIDTH 8
#include "pcre2.h"

#define TRUE 1
#define FALSE 0

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
    context->matched_count = 0;
    context->named_group_count = 0;
    context->matched_results = NULL;
    context->matched_group_results = NULL;
    context->match_data = NULL;
    context->ovector = NULL;
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
}

int64_t match(RegexContext* context, const unsigned char* subject, size_t subject_len, size_t start_offset) {
    if (context->re == NULL) {
        return 0;
    }

    context->match_data = pcre2_match_data_create_from_pattern(context->re, NULL);
    context->matched_count = pcre2_match(
        (pcre2_code*)context->re,
        subject,
        subject_len,
        start_offset,
        context->match_options,
        context->match_data,
        NULL);

    return context->matched_count;
}

void prepare_named_groups(RegexContext* context) {
    if (context->named_group_count > 0) {
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
    int i;
    context->ovector = pcre2_get_ovector_pointer(context->match_data);
    PCRE2_SIZE* ovector = context->ovector;
    for (i = 0; i < context->matched_count; i++) {
        (context->matched_results + i)->start = ovector[2 * i];
        (context->matched_results + i)->len = ovector[2 * i + 1] - ovector[2 * i];
    }

    PCRE2_SPTR name_table;
    uint32_t name_entry_size;
    PCRE2_SPTR tabptr;
    int n;

    if (context->named_group_count > 0) {
        pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_NAMETABLE, &name_table);
        pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_NAMEENTRYSIZE, &name_entry_size);

        tabptr = name_table;
        for (i = 0; i < context->named_group_count; i++) {
            n = (tabptr[0] << 8) | tabptr[1];
            sprintf((context->matched_group_results + i)->name, "%.*s", name_entry_size - 3, tabptr + 2);
            (context->matched_group_results + i)->start = ovector[2 * n];
            (context->matched_group_results + i)->len = ovector[2 * n + 1] - ovector[2 * n];
            tabptr += name_entry_size;
        }
    }
}
