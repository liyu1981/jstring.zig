#include "pcre_binding.h"

#include <signal.h>
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

#define PCRE2_FINE 100  // 100 is pcre2 no error

void reset_context(RegexContext* context) {
    context->error_number = PCRE2_FINE;
    context->error_offset = 0;
    context->error_message_len = 0;

    // intentionally do not reset these 2 options
    // regex_options
    // match_options

    context->with_match_result = FALSE;
    context->next_offset = 0;
    context->origin_offset = 0;
    context->rc = 0;

    context->group_name_count = 0;
    context->group_names = NULL;

    context->matched_count = 0;
    memset(&context->matched_result, 0, sizeof(RegexMatchResult));

    context->matched_group_count = 0;
    context->matched_group_capacity = 0;
    context->matched_group_results = NULL;

    context->re = NULL;
    context->match_data = NULL;
}

uint8_t compile(RegexContext* context, const unsigned char* pattern) {
    reset_context(context);

    pcre2_code* re = pcre2_compile(
        pattern,
        PCRE2_ZERO_TERMINATED,
        context->regex_options,
        &context->error_number,
        &context->error_offset,
        NULL);
    context->re = (void*)re;

    if (re != NULL) {
        uint32_t group_capacity;
        pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_CAPTURECOUNT, &group_capacity);
        context->matched_group_capacity = group_capacity;

        uint32_t group_name_count;
        pcre2_pattern_info(re, PCRE2_INFO_NAMECOUNT, &group_name_count);
        context->group_name_count = group_name_count;

        if (group_name_count > 0) {
            context->group_names = (RegexGroupName*)malloc(sizeof(RegexGroupName) * group_name_count);
            if (context->group_names == NULL) {
                fprintf(stderr, "memory allocation for group names(%d) failed! Abort!", group_name_count); /* no-cover */
                raise(SIGABRT);                                                                            /* no-cover */
            }                                                                                              /* no-cover */

            PCRE2_SPTR name_table;
            uint32_t name_entry_size;
            PCRE2_SPTR tabptr;
            int i;

            pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_NAMETABLE, &name_table);
            pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_NAMEENTRYSIZE, &name_entry_size);
            tabptr = name_table;

            for (i = 0; i < group_name_count; i++) {
                RegexGroupName* group_name_ptr = context->group_names + i;
                group_name_ptr->index = (tabptr[0] << 8) | tabptr[1];
                group_name_ptr->name_len = strlen((const char*)tabptr + 2);          // pcre group name is 0 terminated
                group_name_ptr->name = (char*)malloc(group_name_ptr->name_len + 1);  // +1 for the zero sentinel
                if (group_name_ptr->name == NULL) {
                    fprintf(stderr, "memory allocation for group name (%d bytes) failed! Abort!", (int)group_name_ptr->name_len); /* no-cover */
                    raise(SIGABRT);                                                                                               /* no-cover */
                }                                                                                                                 /* no-cover */
                sprintf(group_name_ptr->name, "%s", tabptr + 2);
                group_name_ptr->name[group_name_ptr->name_len + 1] = 0;
                tabptr += name_entry_size;  // move to next entry
            }
        }
    }

    return re == NULL ? FALSE : TRUE;
}

void free_context(RegexContext* context) {
    if (context->re != NULL) {
        pcre2_code_free((pcre2_code*)context->re);
        if (context->group_name_count > 0) {
            int i;
            for (i = 0; i < context->group_name_count; i++) {
                free(context->group_names[i].name);
            }
            free(context->group_names);
        }
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

    // there is always only one match result if matched, others in rc are group results
    context->matched_count = context->rc > 0 ? 1 : 0;
    context->with_match_result = TRUE;

    context->origin_offset = start_offset;

    return context->rc;
}

void fetch_match_results(RegexContext* context) {
    if (context->with_match_result == FALSE) {
        return;
    }

    int i;
    int j;
    int group_index;
    int name_index;
    int found_group_name_index = -1;
    PCRE2_SPTR name_table;
    uint32_t name_entry_size;
    PCRE2_SPTR tabptr;
    PCRE2_SIZE* ovector = pcre2_get_ovector_pointer(context->match_data);

    pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_NAMETABLE, &name_table);
    pcre2_pattern_info((pcre2_code*)context->re, PCRE2_INFO_NAMEENTRYSIZE, &name_entry_size);

    // for single match
    // 1. if context->rc == 1, means there is only match but no group results
    // 2. if context->rc > 1, means the [0] is match result, but rest are all group results
    //    however count of all groups results can be > named_group_count, which are just unnamed groups

    tabptr = name_table;
    for (i = 0; i < context->rc; i++) {
        if (i == 0) {
            // the first entry is the single match result
            context->matched_result.start = ovector[2 * i];
            context->matched_result.len = ovector[2 * i + 1] - ovector[2 * i];
        } else {
            group_index = i;
            name_index = (tabptr[0] << 8) | tabptr[1];

            found_group_name_index = -1;
            for (j = 0; j < context->group_name_count; j++) {
                // this is stupid, a hash map will be better, but really necessary? are we going to have too many group names?
                if (context->group_names[j].index == group_index) {
                    found_group_name_index = j;
                    break;
                }
            }

            RegexGroupResult* cur_group_result = context->matched_group_results + (group_index - 1);  // -1 because 1st is single match result

            if (found_group_name_index >= 0) {
                cur_group_result->name = context->group_names[found_group_name_index].name;
                cur_group_result->name_len = context->group_names[found_group_name_index].name_len;
                cur_group_result->index = group_index;
                cur_group_result->start = ovector[2 * i];
                cur_group_result->len = ovector[2 * i + 1] - ovector[2 * i];
            } else {
                cur_group_result->name = NULL;
                cur_group_result->name_len = 0;
                cur_group_result->index = group_index;
                cur_group_result->start = ovector[2 * i];
                cur_group_result->len = ovector[2 * i + 1] - ovector[2 * i];
            }

            context->matched_group_count += 1;
        }
    }
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
    // pay attention to not free re, group_names as they should be kept same for next match

    if (context->with_match_result == FALSE) {
        return;
    }

    // if (context->re != NULL) {
    //     pcre2_code_free((pcre2_code*)context->re);
    // }

    if (context->match_data != NULL) {
        pcre2_match_data_free((pcre2_match_data*)context->match_data);
    }

    context->error_number = PCRE2_FINE;
    context->error_offset = 0;
    context->error_message_len = 0;

    context->with_match_result = FALSE;
    context->next_offset = 0;
    context->origin_offset = 0;
    context->rc = 0;

    context->matched_count = 0;
    memset(&context->matched_result, 0, sizeof(RegexMatchResult));

    context->matched_group_count = 0;

    // do not reset group_capacity and matched_group_results mem as they can be reused
    // context->matched_group_capacity = 0;
    // context->matched_group_results = NULL;

    context->match_data = NULL;
    // context->re = NULL;
}
