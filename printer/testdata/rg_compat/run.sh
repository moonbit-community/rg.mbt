mkdir -p out
rg -n -H --no-heading --color=always -e Sherlock sherlock > out/color_basic.out
rg -N -H --no-heading --color=always -e Sherlock sherlock > out/color_no_line_number.out
rg -n --heading -H --color=always -e Sherlock sherlock > out/color_heading.out
rg -n -H --no-heading -C1 --color=always -e Watson sherlock > out/color_context.out
rg -n -H --heading -C1 --color=always -e Watson sherlock > out/color_context_heading.out
rg -n -H --no-heading --column -b --color=always -e Watson sherlock > out/color_column_byte_offset.out
rg -n -H --no-heading -o --color=always -e 'Sherl\w+|Hol\w+' sherlock > out/color_only_matching.out
rg --vimgrep --color=always -e 'Doctor|Holmes' sherlock > out/color_vimgrep.out
rg -n -H --no-heading -r '[$1]' --color=always -e 'Sher(lock)' sherlock > out/color_replace.out
rg -n -o -r '<$0>' --color=always -e 'o[a-z]' sherlock > out/color_replace_only_matching.out
rg -n -H --no-heading -U --color=always -e 'Sherlock\nHolmeses' sherlock > out/color_multiline.out
rg -n -H --no-heading -U -C1 --color=always -e 'luck\. Sherlock Holmes\ncan' sherlock > out/color_multiline_context.out
rg -n -H --no-heading -U -o --color=always -e 'Sherlock\nHolmeses' sherlock > out/color_multiline_only_matching.out
rg --vimgrep -U --color=always -e 'Sherlock\nHolmeses|Watson' sherlock > out/color_multiline_vimgrep.out
rg -n -H --no-heading -M 30 --color=always -e Sherlock sherlock > out/color_max_columns.out
rg -n -H --no-heading -M 30 --max-columns-preview --color=always -e Sherlock sherlock > out/color_max_columns_preview.out
rg -n -M 9 --max-columns-preview --color=always -e Sherlock graph > out/graphemes_max_columns_preview.out
rg -n -H --no-heading --colors match:bg:yellow --colors match:fg:0x10 --colors line:style:underline --colors path:fg:255,0,128 --colors highlight:bg:blue --colors column:fg:cyan --colors column:style:intense --column --color=always -e Sherlock sherlock > out/custom_colors.out
rg -n -H --no-heading --colors match:none --colors path:none -C1 --color=always -e Watson sherlock > out/colors_none.out
rg -n --trim --color=always -e 'Sherlock|Watson' indented > out/trim.out
rg -n --trim -o --color=always -e '\s+\S+' indented > out/trim_only_matching.out
rg -n -H --no-heading -v --color=always -e 'Sherlock|Watson' sherlock > out/invert.out
rg -n -H --no-heading -v -C1 --color=always -e 'Holmeses|cigar' sherlock > out/invert_context.out
rg -n -H --no-heading -C1 --field-match-separator :: --field-context-separator '~~' --context-separator '##' --color=always -e Doctor sherlock > out/separators.out
rg -n -H --no-heading -0 --color=always -e Sherlock sherlock > out/null_terminator.out
rg -n -H --heading -0 --color=always -e Sherlock sherlock > out/null_terminator_heading.out
rg -n -H --no-heading --path-separator @ --color=always -e Sherlock ./sherlock > out/path_separator.out
rg -n -H --no-heading --color=always -e Sherlock bin2 > out/binary_convert.out
rg -n -H --no-heading --color=always -e Sherlock bin1 > out/binary_convert_first.out
rg -n -H --no-heading --color=never -e Sherlock latin1 > out/latin1_no_color.out
rg -n -H --no-heading --hyperlink-format vscode --column --color=always -e Sherlock sherlock > out/hyperlink_vscode.out
rg -n -H --heading --hyperlink-format file --color=always -e Sherlock sherlock > out/hyperlink_heading_file.out
rg -n -H --heading --hyperlink-format kitty --color=always -e Sherlock sherlock > out/hyperlink_heading_kitty.out
rg -n -H --no-heading -C1 --hyperlink-format grep+ --color=always -e Watson sherlock > out/hyperlink_context.out
rg -n --passthru --color=always -e Watson sherlock > out/passthru.out
rg -n -m1 -A2 --color=always -e Doctor sherlock > out/max_count_after.out
rg -n --crlf --color=always -e 'Sherlock$|^can' crlf > out/crlf.out
rg -n --crlf -o --color=always -e '\w+$' crlf > out/crlf_only_matching.out
rg -n -b -o --color=always -e 'o[a-z]' sherlock > out/byte_offset_only_matching.out
rg -n --column -C1 --color=always -e Watson sherlock > out/column_context.out
rg -n -M 20 -C1 --color=always -e Watson sherlock > out/max_columns_context.out
rg -n -o -M 5 --max-columns-preview --color=always -e Sherlock sherlock > out/max_columns_only_matching_preview.out
rg -n -M 10 --max-columns-preview -C1 --color=always -e Watson sherlock > out/max_columns_preview_context.out
rg -n -U -M 10 --max-columns-preview --color=always -e 'Sherlock\nHolmeses' sherlock > out/multiline_max_columns_preview.out
rg -n -U --color=never -e 'Sherlock\nHolmeses' sherlock > out/multiline_no_color.out
rg -n -U --heading -H -b --color=always -e 'Sherlock\nHolmeses' sherlock > out/multiline_heading.out
rg -c -H --color=always -e Sherlock sherlock > out/summary_count.out
rg --count-matches -H --color=always -e o sherlock > out/summary_count_matches.out
rg -l --color=always -e Sherlock sherlock > out/summary_files_with_matches.out
rg -l -0 --color=always -e Sherlock sherlock > out/summary_files_with_matches_null.out
rg --files-without-match --color=always -e ZZZ sherlock > out/summary_files_without_match.out
rg -c -H --hyperlink-format vscode --color=always -e Sherlock sherlock > out/summary_count_hyperlink.out
rg --files --color=always sherlock > out/path_printer_basic.out
rg --files -0 --path-separator @ --hyperlink-format vscode --color=always ./sherlock > out/path_printer_null_sep.out
rg --files --hyperlink-format vscode --color=always ./sherlock > out/path_printer_hyperlink.out
rg --json -e Watson sherlock > out/json_basic.out
rg --json -C1 -e Watson sherlock > out/json_pretty_context.out
rg --json -e Sherlock latin1 > out/json_pretty_non_utf8.out
rg --json -C1 -e Watson sherlock > out/json_context.out
rg --json -r '<$0>' -e 'Sher(lock)' sherlock > out/json_replace.out
rg --json -v -n -e o sherlock > out/json_invert.out
rg --json -e Sherlock latin1 > out/json_non_utf8.out
rg --json -e Sherlock bin2 > out/json_binary.out
rg --json -U -e 'Sherlock\nHolmeses' sherlock > out/json_multiline.out
