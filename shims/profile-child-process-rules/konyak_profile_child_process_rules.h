#ifndef KONYAK_PROFILE_CHILD_PROCESS_RULES_H
#define KONYAK_PROFILE_CHILD_PROCESS_RULES_H

/*
 * Konyak profile rules use one line per child argument:
 *
 *   <executable suffix>\t<argument>\n
 *
 * The parent process owns this environment variable. This hook never runs a
 * shell, loads external code, or selects application-specific behavior.
 */
#define KONYAK_CHILD_PROCESS_RULES_ENV L"KONYAK_CHILD_PROCESS_RULES"
#define KONYAK_MAX_CHILD_PROCESS_RULE_ARGUMENTS 64
#define KONYAK_MAX_CHILD_PROCESS_RULES_LENGTH 65536

static BOOL konyak_rule_path_ends_with( const WCHAR *path, const WCHAR *suffix )
{
    size_t path_length, suffix_length, index;

    if (!path || !suffix || !suffix[0]) return FALSE;

    path_length = lstrlenW( path );
    suffix_length = lstrlenW( suffix );
    if (path_length < suffix_length) return FALSE;

    path += path_length - suffix_length;
    for (index = 0; index < suffix_length; ++index)
    {
        WCHAR left = path[index];
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

static BOOL konyak_rule_command_line_contains( const WCHAR *command_line, const WCHAR *argument )
{
    const WCHAR *match = command_line;
    size_t argument_length;

    if (!command_line || !argument || !argument[0]) return FALSE;

    argument_length = lstrlenW( argument );
    while ((match = wcsstr( match, argument )))
    {
        WCHAR before = match == command_line ? 0 : match[-1];
        WCHAR after = match[argument_length];

        if (konyak_rule_command_line_delimiter( before ) &&
            konyak_rule_command_line_delimiter( after ))
            return TRUE;
        match += argument_length;
    }

    return FALSE;
}

static BOOL konyak_rule_arguments_contain( const WCHAR *const *arguments, unsigned int count,
                                           const WCHAR *candidate )
{
    unsigned int index;

    for (index = 0; index < count; ++index)
        if (!wcsicmp( arguments[index], candidate )) return TRUE;
    return FALSE;
}

static WCHAR *konyak_child_process_command_line( const WCHAR *application_name,
                                                  const WCHAR *command_line )
{
    const WCHAR *arguments[KONYAK_MAX_CHILD_PROCESS_RULE_ARGUMENTS];
    WCHAR *rules, *cursor, *line, *result, *write;
    DWORD required_length, read_length;
    unsigned int argument_count = 0, index;
    size_t result_length;

    if (!application_name || !command_line) return NULL;

    required_length = GetEnvironmentVariableW( KONYAK_CHILD_PROCESS_RULES_ENV, NULL, 0 );
    if (!required_length || required_length > KONYAK_MAX_CHILD_PROCESS_RULES_LENGTH) return NULL;
    if (!(rules = RtlAllocateHeap( GetProcessHeap(), 0,
                                  KONYAK_MAX_CHILD_PROCESS_RULES_LENGTH * sizeof(WCHAR) )))
        return NULL;
    read_length = GetEnvironmentVariableW( KONYAK_CHILD_PROCESS_RULES_ENV, rules,
                                           KONYAK_MAX_CHILD_PROCESS_RULES_LENGTH );
    if (!read_length || read_length >= KONYAK_MAX_CHILD_PROCESS_RULES_LENGTH)
    {
        RtlFreeHeap( GetProcessHeap(), 0, rules );
        return NULL;
    }

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
                konyak_rule_path_ends_with( application_name, target ) &&
                !konyak_rule_command_line_contains( command_line, argument ) &&
                !konyak_rule_arguments_contain( arguments, argument_count, argument ) &&
                argument_count < KONYAK_MAX_CHILD_PROCESS_RULE_ARGUMENTS)
                arguments[argument_count++] = argument;
        }

        if (!delimiter) break;
        line = cursor + 1;
    }

    if (!argument_count)
    {
        RtlFreeHeap( GetProcessHeap(), 0, rules );
        return NULL;
    }

    result_length = lstrlenW( command_line ) + 1;
    for (index = 0; index < argument_count; ++index)
        result_length += lstrlenW( arguments[index] ) + 1;
    if (!(result = RtlAllocateHeap( GetProcessHeap(), 0, result_length * sizeof(WCHAR) )))
    {
        RtlFreeHeap( GetProcessHeap(), 0, rules );
        return NULL;
    }

    lstrcpyW( result, command_line );
    write = result + lstrlenW( result );
    for (index = 0; index < argument_count; ++index)
    {
        *write++ = ' ';
        lstrcpyW( write, arguments[index] );
        write += lstrlenW( write );
    }

    RtlFreeHeap( GetProcessHeap(), 0, rules );
    return result;
}

#endif
