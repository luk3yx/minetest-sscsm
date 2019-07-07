--
-- A primitive code minifier
--
-- © 2019 by luk3yx
--

return function(code)
    assert(type(code) == 'string')

    local res, last, ws1, ws2, escape = '', false, '\n', '\n', false
    local sp = {['"'] = true, ["'"] = true}

    for i = 1, #code do
        local char = code:sub(i, i)
        if char == '\r' then char = '\n' end
        if last == '--' or last == '--.' or last == '--[' then
            ws1 = ws2
            if char == '\n' then
                if ws1 ~= '\n' then res = res .. '\n' end
                last = false
                ws1 = '\n'
            elseif char == '[' and last ~= '--.' then
                last = last .. char
            else
                last = '--.'
            end
        elseif last == '--[[' or last == '-]' then
            ws1 = ws2
            if last == '-]' then
                if char == ']' then
                    last = false
                else
                    last = '--[['
                end
            elseif char == ']' then
                last = '-]'
            end
        elseif last == '[[' or last == ']' then
            if last == ']' then
                if char == ']' then
                    last = false
                else
                    last = '[['
                end
            elseif char == ']' then
                last = ']'
            end
            res = res .. char
        elseif escape then
            res = res .. '\\' .. char
            escape = false
        elseif char == '\\' then
            escape = true
        elseif last == '"' or last == "'" then
            if char == last then last = false end
            res = res .. char
        elseif last == '-' then
            if char == '-' then
                last, ws1 = '--', ws2
            else
                res = res .. '-' .. char
                last, ws1 = false, false
            end
        elseif char == '-' then
            last = char
            ws1 = ws2
        elseif char == '\n' then
            if ws2 == ' ' then
                res = res:sub(1, #res - 1) .. '\n'
            elseif ws2 ~= '\n' then
                res = res .. '\n'
            end
            ws1 = '\n'
        elseif char == ' ' or char == '\t' then
            if not ws2 then res = res .. ' ' end
            ws1 = ws2 or ' '
        else
            if sp[char] then last = char end
            res = res .. char
        end

        ws2 = ws1
        ws1 = false
    end

    return res
end
