#ifndef KONYAK_PROFILE_CHILD_PROCESS_RULES_H
#define KONYAK_PROFILE_CHILD_PROCESS_RULES_H

/*
 * One validated child argument per line:
 *
 *   <executable suffix>\t<argument>\n
 *
 * Konyak selects profiles outside Wine. This hook only applies the serialized
 * rules at the NtCreateUserProcess boundary and contains no application data.
 */
#define KONYAK_CHILD_PROCESS_RULES_ENV "KONYAK_CHILD_PROCESS_RULES"
#define KONYAK_MAX_CHILD_PROCESS_RULE_ARGUMENTS 64
#define KONYAK_MAX_CHILD_PROCESS_RULES_UTF8_LENGTH (4 * 65535)

struct konyak_child_process_command_line
{
    UNICODE_STRING original;
    WCHAR *buffer;
};

static BOOL konyak_rule_path_ends_with( const UNICODE_STRING *path, const WCHAR *suffix )
{
    SIZE_T path_length, suffix_length, index;

    if (!path || !path->Buffer || !suffix || !suffix[0]) return FALSE;

    path_length = path->Length / sizeof(WCHAR);
    suffix_length = wcslen( suffix );
    if (path_length < suffix_length) return FALSE;

    for (index = 0; index < suffix_length; ++index)
    {
        WCHAR left = path->Buffer[path_length - suffix_length + index];
        WCHAR right = suffix[index];

        if (left >= 'A' && left <= 'Z') left += 'a' - 'A';
        if (right >= 'A' && right <= 'Z') right += 'a' - 'A';
        if (left != right) return FALSE;
    }
    return TRUE;
}

static BOOL konyak_rule_command_line_delimiter( WCHAR character )
{
    return !character || character == ' ' || character == '\t' || character == '"';
}

static BOOL konyak_rule_command_line_contains( const UNICODE_STRING *command_line,
                                               const WCHAR *argument )
{
    SIZE_T command_length, argument_length, index;

    if (!command_line || !command_line->Buffer || !argument || !argument[0]) return FALSE;

    command_length = command_line->Length / sizeof(WCHAR);
    argument_length = wcslen( argument );
    if (argument_length > command_length) return FALSE;

    for (index = 0; index + argument_length <= command_length; ++index)
    {
        WCHAR before, after;

        if (wcsncmp( command_line->Buffer + index, argument, argument_length )) continue;
        before = index ? command_line->Buffer[index - 1] : 0;
        after = index + argument_length < command_length
            ? command_line->Buffer[index + argument_length] : 0;
        if (konyak_rule_command_line_delimiter( before ) &&
            konyak_rule_command_line_delimiter( after )) return TRUE;
    }
    return FALSE;
}

static BOOL konyak_rule_arguments_contain( const WCHAR *const *arguments, unsigned int count,
                                           const WCHAR *candidate )
{
    unsigned int index;

    for (index = 0; index < count; ++index)
        if (!ntdll_wcsicmp( arguments[index], candidate )) return TRUE;
    return FALSE;
}

static void konyak_apply_child_process_rules( RTL_USER_PROCESS_PARAMETERS *params,
                                              struct konyak_child_process_command_line *state )
{
    const char *serialized = getenv( KONYAK_CHILD_PROCESS_RULES_ENV );
    const WCHAR *arguments[KONYAK_MAX_CHILD_PROCESS_RULE_ARGUMENTS];
    WCHAR *rules, *cursor, *line, *result, *write;
    SIZE_T serialized_length, command_length, result_length;
    DWORD converted_length;
    unsigned int argument_count = 0, index;

    if (!params || !serialized || !serialized[0]) return;
    serialized_length = strlen( serialized );
    if (serialized_length > KONYAK_MAX_CHILD_PROCESS_RULES_UTF8_LENGTH) return;

    if (!(rules = malloc( (serialized_length + 1) * sizeof(WCHAR) ))) return;
    converted_length = ntdll_umbstowcs( serialized, serialized_length + 1,
                                        rules, serialized_length + 1 );
    if (!converted_length || converted_length > serialized_length + 1)
    {
        free( rules );
        return;
    }
    rules[serialized_length] = 0;

    line = rules;
    for (cursor = rules;; ++cursor)
    {
        WCHAR delimiter = *cursor;
        WCHAR *separator, *target, *argument;

        if (delimiter && delimiter != '\r' && delimiter != '\n') continue;
        *cursor = 0;
        target = line;
        separator = wcschr( line, '\t' );
        if (separator)
        {
            *separator = 0;
            argument = separator + 1;
            if (target[0] && argument[0] &&
                konyak_rule_path_ends_with( &params->ImagePathName, target ) &&
                !konyak_rule_command_line_contains( &params->CommandLine, argument ) &&
                !konyak_rule_arguments_contain( arguments, argument_count, argument ) &&
                argument_count < KONYAK_MAX_CHILD_PROCESS_RULE_ARGUMENTS)
                arguments[argument_count++] = argument;
        }

        if (!delimiter) break;
        line = cursor + 1;
    }

    if (!argument_count)
    {
        free( rules );
        return;
    }

    command_length = params->CommandLine.Length / sizeof(WCHAR);
    result_length = command_length;
    for (index = 0; index < argument_count; ++index)
        result_length += wcslen( arguments[index] ) + 1;
    if ((result_length + 1) * sizeof(WCHAR) > 0xffff ||
        !(result = malloc( (result_length + 1) * sizeof(WCHAR) )))
    {
        free( rules );
        return;
    }

    memcpy( result, params->CommandLine.Buffer, params->CommandLine.Length );
    write = result + command_length;
    for (index = 0; index < argument_count; ++index)
    {
        SIZE_T argument_length = wcslen( arguments[index] );

        *write++ = ' ';
        memcpy( write, arguments[index], argument_length * sizeof(WCHAR) );
        write += argument_length;
    }
    *write = 0;

    state->original = params->CommandLine;
    state->buffer = result;
    params->CommandLine.Buffer = result;
    params->CommandLine.Length = result_length * sizeof(WCHAR);
    params->CommandLine.MaximumLength = (result_length + 1) * sizeof(WCHAR);
    free( rules );
}

static void konyak_restore_child_process_command_line( RTL_USER_PROCESS_PARAMETERS *params,
                                                       struct konyak_child_process_command_line *state )
{
    if (!state->buffer) return;
    params->CommandLine = state->original;
    free( state->buffer );
    state->buffer = NULL;
}

#endif
