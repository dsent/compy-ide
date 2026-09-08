--------------------------------------------------------------------------------
-- Copyright (c) 2006-2014 Fabien Fleutot and others.
--
-- Made available under the terms of the MIT public license, which
-- accompanies this distribution in LICENSE and is available at
-- http://www.lua.org/license.html
--
-- Contributors:
--     Fabien Fleutot - API and implementation
--
--------------------------------------------------------------------------------

----------------------------------------------------------------------
-- Generate a new lua-specific lexer, derived from the generic lexer.
----------------------------------------------------------------------

local generic_lexer = require 'metalua.grammar.lexer'

return function()
    local lexer = generic_lexer.lexer :clone()

    local keywords = {
        "and", "break", "do", "else", "elseif",
        "end", "false", "for", "function",
        "goto", -- Lua5.2
        "if",
        "in", "local", "nil", "not", "or", "repeat",
        "return", "then", "true", "until", "while",
        "...", "..", "==", ">=", "<=", "~=",
        "::", -- Lua5,2
        "+{", "-{" } -- Metalua

    for _, w in ipairs(keywords) do lexer :add (w) end

    return lexer
end