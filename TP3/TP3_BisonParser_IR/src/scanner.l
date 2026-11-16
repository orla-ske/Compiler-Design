%option noyywrap nodefault nounput yylineno

%{
#include <string>
#include <vector>
#include <stdexcept>
#include "tokens.hpp"
#include <cstdio>

// Match Flex-generated declarations (C++ linkage) DO NOT EDIT
typedef struct yy_buffer_state *YY_BUFFER_STATE;
int yylex(void);
void yyrestart(FILE*);
YY_BUFFER_STATE yy_scan_string(const char* str);
void yy_delete_buffer(YY_BUFFER_STATE b);

static std::vector<Token>* g_tokens = nullptr;
static YY_BUFFER_STATE g_buf = nullptr;
static std::vector<std::string> g_errors;
static int g_comment_line = 0;

static void emit(TokenType type, const std::string& value) {
    g_tokens->push_back(Token{type, value, yylineno});
}

static void lex_error(int line, const std::string& msg) {
    g_errors.push_back("lexical error, line " + std::to_string(line) + ": " + msg);
}

// throws once with every lexical error found
static void raise_errors() {
    if (g_errors.empty()) return;
    std::string all;
    for (const auto& e : g_errors) all += e + "\n";
    all += std::to_string(g_errors.size()) + " lexical error(s)";
    g_errors.clear();
    throw std::runtime_error(all);
}

void scan_to_tokens(std::vector<Token>& out) {
    g_tokens = &out;
    yylineno = 1;
    yyrestart(nullptr);
    yylex();
    raise_errors();
}

void scan_string_to_tokens(const std::string& src, std::vector<Token>& out) {
    g_tokens = &out;
    yylineno = 1;
    g_buf = yy_scan_string(src.c_str());
    yylex();
    yy_delete_buffer(g_buf);
    g_buf = nullptr;
    raise_errors();
}

%}

%x COMMENT

DIGIT       [0-9]
HEX_DIGIT   [0-9A-Fa-f]
BIN_DIGIT   [01]
LETTER      [A-Za-z]

DECIMAL     {DIGIT}(_?{DIGIT})*
HEX         0[xX]{HEX_DIGIT}(_?{HEX_DIGIT})*
BINARY      0[bB]{BIN_DIGIT}(_?{BIN_DIGIT})*
WORD        ({LETTER}|_)({LETTER}|{DIGIT}|_)*
ESCAPE      \\[ntrfb"\\]

%%

[ \t\r\f]+              ;
\n                      ;
"//"[^\n]*              ;

"/*"                    { g_comment_line = yylineno; BEGIN(COMMENT); }
<COMMENT>"*/"           { BEGIN(INITIAL); }
<COMMENT>[^*\n]+        ;
<COMMENT>"*"            ;
<COMMENT>\n             ;
<COMMENT><<EOF>>        {
                            lex_error(g_comment_line, "unterminated block comment");
                            BEGIN(INITIAL);
                            emit(TokenType::End, "END");
                            return 0;
                        }

"int"                   { emit(TokenType::Int, yytext); }
"bool"                  { emit(TokenType::Bool, yytext); }
"const"                 { emit(TokenType::Const, yytext); }
"true"                  { emit(TokenType::True, yytext); }
"false"                 { emit(TokenType::False, yytext); }
"if"                    { emit(TokenType::If, yytext); }
"else"                  { emit(TokenType::Else, yytext); }
"while"                 { emit(TokenType::While, yytext); }
"do"                    { emit(TokenType::Do, yytext); }
"for"                   { emit(TokenType::For, yytext); }
"break"                 { emit(TokenType::Break, yytext); }
"continue"              { emit(TokenType::Continue, yytext); }
"print"                 { emit(TokenType::Print, yytext); }
"prints"                { emit(TokenType::Prints, yytext); }
"read"                  { emit(TokenType::Read, yytext); }

{WORD}                  { emit(TokenType::Identifier, yytext); }

{DECIMAL}|{HEX}|{BINARY} {
                            int64_t value;
                            if (parse_int_literal(yytext, value))
                                emit(TokenType::IntLit, yytext);
                            else
                                lex_error(yylineno, std::string("integer literal out of range '") + yytext + "'");
                        }
{DIGIT}({LETTER}|{DIGIT}|_)* {
                            lex_error(yylineno, std::string("malformed number '") + yytext + "'");
                        }

\"([^"\\\n]|{ESCAPE})*\" { emit(TokenType::String, std::string(yytext + 1, yyleng - 2)); }
\"([^"\\\n]|\\.)*\"     { lex_error(yylineno, std::string("invalid escape in string ") + yytext); }
\"([^"\\\n]|\\.)*       { lex_error(yylineno, "unterminated string"); }

"<<="                   { emit(TokenType::ShlAssign, yytext); }
">>="                   { emit(TokenType::ShrAssign, yytext); }
"+="                    { emit(TokenType::PlusAssign, yytext); }
"-="                    { emit(TokenType::MinusAssign, yytext); }
"*="                    { emit(TokenType::StarAssign, yytext); }
"/="                    { emit(TokenType::SlashAssign, yytext); }
"%="                    { emit(TokenType::PercentAssign, yytext); }
"&="                    { emit(TokenType::AndAssign, yytext); }
"|="                    { emit(TokenType::OrAssign, yytext); }
"^="                    { emit(TokenType::XorAssign, yytext); }
"++"                    { emit(TokenType::Increment, yytext); }
"--"                    { emit(TokenType::Decrement, yytext); }
"=="                    { emit(TokenType::Eq, yytext); }
"!="                    { emit(TokenType::Neq, yytext); }
"<="                    { emit(TokenType::Le, yytext); }
">="                    { emit(TokenType::Ge, yytext); }
"<<"                    { emit(TokenType::Shl, yytext); }
">>"                    { emit(TokenType::Shr, yytext); }
"&&"                    { emit(TokenType::And, yytext); }
"||"                    { emit(TokenType::Or, yytext); }
"**"                    { emit(TokenType::Power, yytext); }
"="                     { emit(TokenType::Assign, yytext); }
"<"                     { emit(TokenType::Lt, yytext); }
">"                     { emit(TokenType::Gt, yytext); }
"+"                     { emit(TokenType::Plus, yytext); }
"-"                     { emit(TokenType::Minus, yytext); }
"*"                     { emit(TokenType::Star, yytext); }
"/"                     { emit(TokenType::Slash, yytext); }
"%"                     { emit(TokenType::Percent, yytext); }
"&"                     { emit(TokenType::BitAnd, yytext); }
"|"                     { emit(TokenType::BitOr, yytext); }
"^"                     { emit(TokenType::BitXor, yytext); }
"~"                     { emit(TokenType::BitNot, yytext); }
"!"                     { emit(TokenType::Not, yytext); }

"("                     { emit(TokenType::LParen, yytext); }
")"                     { emit(TokenType::RParen, yytext); }
"{"                     { emit(TokenType::LBrace, yytext); }
"}"                     { emit(TokenType::RBrace, yytext); }
"["                     { emit(TokenType::LBracket, yytext); }
"]"                     { emit(TokenType::RBracket, yytext); }
";"                     { emit(TokenType::Semicolon, yytext); }
","                     { emit(TokenType::Comma, yytext); }
"?"                     { emit(TokenType::Question, yytext); }
":"                     { emit(TokenType::Colon, yytext); }

.                       { lex_error(yylineno, std::string("unexpected character '") + yytext + "'"); }

<<EOF>>                 {
                            emit(TokenType::End, "END");
                            return 0;
                        }

%%
