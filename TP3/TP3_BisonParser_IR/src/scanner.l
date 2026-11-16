%option noyywrap nodefault nounput noinput yylineno

%{
#include <cctype>
#include <cstdint>
#include <string>
#include <vector>
#include <stdexcept>
#include "tokens.hpp"
#include "parser.tab.hpp" // token ids and yystype from bison

/* yylval is defined in parser.tab.cpp */
extern YYSTYPE yylval;

/* scanner api used by main.cpp */
typedef struct yy_buffer_state *YY_BUFFER_STATE;
int yylex(void);
void yyrestart(FILE*);
YY_BUFFER_STATE yy_scan_string(const char* str);
void yy_delete_buffer(YY_BUFFER_STATE b);

static int g_comment_line = 0;

/* merged: our tp2 error message format, thrown at once because bison pulls one token at a time */
[[noreturn]] static void lex_error(int line, const std::string& msg) {
    throw std::runtime_error("lexical error, line " + std::to_string(line) + ": " + msg);
}

/* merged: our tp2 parse_int_literal, false when the value exceeds int64 */
static bool parse_int_literal(const std::string& text, int64_t& out) {
    int base = 10;
    size_t i = 0;
    if (text.size() > 1 && (text[1] == 'x' || text[1] == 'X')) { base = 16; i = 2; }
    else if (text.size() > 1 && (text[1] == 'b' || text[1] == 'B')) { base = 2; i = 2; }

    uint64_t value = 0;
    for (; i < text.size(); i++) {
        char c = text[i];
        if (c == '_') continue;
        uint64_t d = std::isdigit((unsigned char)c) ? c - '0' : std::tolower((unsigned char)c) - 'a' + 10;
        if (value > (uint64_t(INT64_MAX) - d) / base) return false;
        value = value * base + d;
    }
    out = (int64_t)value;
    return true;
}
%}

DIGIT      [0-9]
ID_START   [A-Za-z_]
ID_CONT    [A-Za-z0-9_]
WS         [ \t\r\f]+
NL         [\n]

/* merged: our tp2 literal forms */
HEX_DIGIT  [0-9A-Fa-f]
BIN_DIGIT  [01]
DECIMAL    {DIGIT}(_?{DIGIT})*
HEX        0[xX]{HEX_DIGIT}(_?{HEX_DIGIT})*
BINARY     0[bB]{BIN_DIGIT}(_?{BIN_DIGIT})*
ESCAPE     \\[ntrfb"\\]

%x COMMENT

%%

"#"[^\n]* ; /* comment */

 /* merged: our tp2 line and block comments, next to his # comments */
"//"[^\n]*               ;
"/*"                     { g_comment_line = yylineno; BEGIN(COMMENT); }
<COMMENT>"*/"            { BEGIN(INITIAL); }
<COMMENT>[^*\n]+         ;
<COMMENT>"*"             ;
<COMMENT>\n              ;
<COMMENT><<EOF>>         { BEGIN(INITIAL); lex_error(g_comment_line, "unterminated block comment"); }

 /* merged: our tp2 string checks, his token return */
\"([^"\\\n]|{ESCAPE})*\" {
    yylval.token = Token{TokenType::String, std::string(yytext + 1, yyleng - 2), yylineno};
    return T_STRING;
}
\"([^"\\\n]|\\.)*\"      { lex_error(yylineno, std::string("invalid escape in string ") + yytext); }
\"([^"\\\n]|\\.)*        { lex_error(yylineno, "unterminated string"); }


"=="|">="|"<="|"!="      {
    yylval.token = Token{TokenType::Comparison,
                              std::string(yytext, yyleng), yylineno};
    return T_COMPARISON;
}


"+"                      { return '+'; }
"-"                      { return '-'; }
"*"                      { return '*'; }
"/"                      { return '/'; }
"="                      { return T_ASSIGN; }
"("                      { return T_LPAREN; }
")"                      { return T_RPAREN; }
"{"                      { return T_LBRACE; }
"}"                      { return T_RBRACE; }
";"                      { return T_SEMICOLON; }
","                      { return ','; }


"<"|">"                  {
    yylval.token = Token{TokenType::Comparison,
                              std::string(yytext, yyleng), yylineno};
    return T_COMPARISON;
}


{ID_START}{ID_CONT}* {
    std::string s(yytext, yyleng);

    if      (s == "if")     return T_IF;
    else if (s == "else")   return T_ELSE;
    else if (s == "while")  return T_WHILE;
    else if (s == "int")    return T_INT;
    else if (s == "print")  return T_PRINT;
    else if (s == "prints") return T_PRINTS;
    else if (s == "string") return T_STRINGKW;
    else {
        /* variables are stored with a v prefix */
        yylval.token = Token{TokenType::Var, "V" + s, yylineno};
        return T_VAR;
    }
}

 /* merged: our tp2 hex, binary, separators and range check, his token return */
 /* the value is passed on in decimal so later stages never see a prefix or separator */
{DECIMAL}|{HEX}|{BINARY} {
    int64_t value;
    if (!parse_int_literal(yytext, value))
        lex_error(yylineno, std::string("integer literal out of range '") + yytext + "'");
    yylval.token = Token{TokenType::IntLit, std::to_string(value), yylineno};
    return T_INTLIT;
}
{DIGIT}{ID_CONT}*        { lex_error(yylineno, std::string("malformed number '") + yytext + "'"); }

{WS}                     ;
{NL}                     ;

 /* merged: our tp2 message naming the character, his immediate throw */
.                        { lex_error(yylineno, std::string("unexpected character '") + yytext + "'"); }

<<EOF>>                  {
    /* 0 tells bison the input is over */
    return 0;
}

%%
