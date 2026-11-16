#pragma once
#include <cctype>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

enum class TokenType
{
    // keywords
    Int, Bool, Const, True, False,
    If, Else, While, Do, For, Break, Continue,
    Print, Prints, Read,

    // names and literals
    Identifier, IntLit, String,

    // assignment
    Assign, PlusAssign, MinusAssign, StarAssign, SlashAssign, PercentAssign,
    AndAssign, OrAssign, XorAssign, ShlAssign, ShrAssign,
    Increment, Decrement,

    // operators
    Eq, Neq, Lt, Le, Gt, Ge,
    Plus, Minus, Star, Slash, Percent, Power,
    BitAnd, BitOr, BitXor, BitNot, Shl, Shr,
    And, Or, Not,

    // punctuation
    LParen, RParen, LBrace, RBrace, LBracket, RBracket,
    Semicolon, Comma, Question, Colon,

    End
};

struct Token
{
    TokenType type;
    std::string value;
    int line;
};

// readable form of a token for error messages
inline std::string describe(const Token &t)
{
    switch (t.type)
    {
    case TokenType::End:        return "end of file";
    case TokenType::Identifier: return "identifier '" + t.value + "'";
    case TokenType::IntLit:     return "number " + t.value;
    case TokenType::String:     return "string \"" + t.value + "\"";
    default:                    return "'" + t.value + "'";
    }
}

// parses decimal, 0x or 0b literal, false on int64 overflow
inline bool parse_int_literal(const std::string &text, int64_t &out)
{
    int base = 10;
    size_t i = 0;
    if (text.size() > 1 && (text[1] == 'x' || text[1] == 'X')) { base = 16; i = 2; }
    else if (text.size() > 1 && (text[1] == 'b' || text[1] == 'B')) { base = 2; i = 2; }

    uint64_t value = 0;
    for (; i < text.size(); i++)
    {
        char c = text[i];
        if (c == '_') continue;
        uint64_t d = std::isdigit((unsigned char)c) ? c - '0' : std::tolower((unsigned char)c) - 'a' + 10;
        if (value > (uint64_t(INT64_MAX) - d) / base) return false;
        value = value * base + d;
    }
    out = (int64_t)value;
    return true;
}

class TokenArray
{
public:
    void push(const Token &t) { tokens.push_back(t); }
    const Token &current() const
    {
        if (pos >= tokens.size())
            throw std::out_of_range("token pos");
        return tokens[pos];
    }
    void next()
    {
        if (pos + 1 < tokens.size())
            ++pos;
    }
    bool empty() const { return tokens.empty(); }
    void appendEndIfMissing()
    {
        if (tokens.empty() || tokens.back().type != TokenType::End)
            tokens.push_back(Token{TokenType::End, "END", tokens.empty() ? 1 : tokens.back().line});
    }
    std::vector<Token> tokens;
    size_t pos{0};
};
