%{
#include <iostream>
#include <fstream>
#include <string>
#include <cstdint>

static int errors = 0;
static int comment_line = 0;

static void token(const char* name, const char* text) {
    std::cout << name << ": " << text << "\n";
}

static void error(int line, const std::string& msg) {
    std::cerr << "lexical error, line " << line << ": " << msg << "\n";
    errors++;
}

// parses a literal, false if above int64 max
static bool int_value(const std::string& text, uint64_t& value) {
    int base = 10;
    size_t i = 0;
    if (text.size() > 1 && (text[1] == 'x' || text[1] == 'X')) { base = 16; i = 2; }
    else if (text.size() > 1 && (text[1] == 'b' || text[1] == 'B')) { base = 2; i = 2; }

    value = 0;
    for (; i < text.size(); i++) {
        char c = text[i];
        if (c == '_') continue;
        int d = isdigit(c) ? c - '0' : (tolower(c) - 'a' + 10);
        if (value > (uint64_t(INT64_MAX) - d) / base) return false;
        value = value * base + d;
    }
    return true;
}
%}

%option c++
%option yylineno

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
STRING      \"([^"\\\n]|{ESCAPE})*\"

%%

[ \t\r\n]+              ;
"//"[^\n]*              ;

"/*"                    { comment_line = yylineno; BEGIN(COMMENT); }
<COMMENT>"*/"           { BEGIN(INITIAL); }
<COMMENT>[^*\n]+        ;
<COMMENT>"*"            ;
<COMMENT>\n             ;
<COMMENT><<EOF>>        { error(comment_line, "unterminated block comment"); yyterminate(); }

"int"                   { token("INT_TOKEN", yytext); }
"bool"                  { token("BOOL_TOKEN", yytext); }
"const"                 { token("CONST_TOKEN", yytext); }
"true"|"false"          { token("BOOL_LITERAL_TOKEN", yytext); }
"if"                    { token("IF_TOKEN", yytext); }
"else"                  { token("ELSE_TOKEN", yytext); }
"while"                 { token("WHILE_TOKEN", yytext); }
"do"                    { token("DO_TOKEN", yytext); }
"for"                   { token("FOR_TOKEN", yytext); }
"break"                 { token("BREAK_TOKEN", yytext); }
"continue"              { token("CONTINUE_TOKEN", yytext); }
"print"                 { token("PRINT_TOKEN", yytext); }
"prints"                { token("PRINTS_TOKEN", yytext); }
"read"                  { token("READ_TOKEN", yytext); }

{WORD}                  { token("IDENTIFIER_TOKEN", yytext); }

{DECIMAL}|{HEX}|{BINARY} {
                            uint64_t value;
                            if (!int_value(yytext, value))
                                error(yylineno, std::string("integer literal out of range '") + yytext + "'");
                            else
                                std::cout << "INTEGER_LITERAL_TOKEN: " << yytext << " (" << value << ")\n";
                        }
{DIGIT}({LETTER}|{DIGIT}|_)* {
                            error(yylineno, std::string("malformed number '") + yytext + "'");
                        }

{STRING}                { token("STRING_LITERAL_TOKEN", yytext); }
\"([^"\\\n]|\\.)*\"     { error(yylineno, std::string("invalid escape in string ") + yytext); }
\"([^"\\\n]|\\.)*       { error(yylineno, "unterminated string"); }

"<<="                   { token("SHL_ASSIGN_TOKEN", yytext); }
">>="                   { token("SHR_ASSIGN_TOKEN", yytext); }
"+="                    { token("PLUS_ASSIGN_TOKEN", yytext); }
"-="                    { token("MINUS_ASSIGN_TOKEN", yytext); }
"*="                    { token("STAR_ASSIGN_TOKEN", yytext); }
"/="                    { token("SLASH_ASSIGN_TOKEN", yytext); }
"%="                    { token("PERCENT_ASSIGN_TOKEN", yytext); }
"&="                    { token("AND_ASSIGN_TOKEN", yytext); }
"|="                    { token("OR_ASSIGN_TOKEN", yytext); }
"^="                    { token("XOR_ASSIGN_TOKEN", yytext); }
"++"                    { token("INCREMENT_TOKEN", yytext); }
"--"                    { token("DECREMENT_TOKEN", yytext); }
"=="                    { token("EQ_TOKEN", yytext); }
"!="                    { token("NEQ_TOKEN", yytext); }
"<="                    { token("LE_TOKEN", yytext); }
">="                    { token("GE_TOKEN", yytext); }
"<<"                    { token("SHL_TOKEN", yytext); }
">>"                    { token("SHR_TOKEN", yytext); }
"&&"                    { token("AND_TOKEN", yytext); }
"||"                    { token("OR_TOKEN", yytext); }
"**"                    { token("POWER_TOKEN", yytext); }
"="                     { token("ASSIGN_TOKEN", yytext); }
"<"                     { token("LT_TOKEN", yytext); }
">"                     { token("GT_TOKEN", yytext); }
"+"                     { token("PLUS_TOKEN", yytext); }
"-"                     { token("MINUS_TOKEN", yytext); }
"*"                     { token("STAR_TOKEN", yytext); }
"/"                     { token("SLASH_TOKEN", yytext); }
"%"                     { token("PERCENT_TOKEN", yytext); }
"&"                     { token("BIT_AND_TOKEN", yytext); }
"|"                     { token("BIT_OR_TOKEN", yytext); }
"^"                     { token("BIT_XOR_TOKEN", yytext); }
"~"                     { token("BIT_NOT_TOKEN", yytext); }
"!"                     { token("NOT_TOKEN", yytext); }

"("                     { token("LPAREN_TOKEN", yytext); }
")"                     { token("RPAREN_TOKEN", yytext); }
"{"                     { token("LBRACE_TOKEN", yytext); }
"}"                     { token("RBRACE_TOKEN", yytext); }
"["                     { token("LBRACKET_TOKEN", yytext); }
"]"                     { token("RBRACKET_TOKEN", yytext); }
";"                     { token("SEMICOLON_TOKEN", yytext); }
","                     { token("COMMA_TOKEN", yytext); }
"?"                     { token("QUESTION_TOKEN", yytext); }
":"                     { token("COLON_TOKEN", yytext); }

.                       { error(yylineno, std::string("unexpected character '") + yytext + "'"); }

%%

int yyFlexLexer::yywrap() { return 1; }

int main(int argc, char** argv) {
    std::ifstream file;
    if (argc > 1) {
        file.open(argv[1]);
        if (!file) {
            std::cerr << "cannot open " << argv[1] << "\n";
            return 1;
        }
    }

    yyFlexLexer lexer(argc > 1 ? &file : &std::cin);
    lexer.yylex();

    if (errors > 0) std::cerr << errors << " lexical error(s)\n";
    return errors > 0 ? 1 : 0;
}
