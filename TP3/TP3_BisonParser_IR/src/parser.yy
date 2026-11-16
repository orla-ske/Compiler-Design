/* 1. preamble */
%{
#include <iostream>
#include <memory>
#include <string>
#include <stdexcept>

#include "ast.hpp"     // your ast node definitions
#include "tokens.hpp"  // your token struct and tokentype enum

// forward declare the scanner function (defined in flex)
extern int yylex();
extern int yylineno;
extern char *yytext;

// forward declare the error function
void yyerror(const char *s);

// this will hold the final, complete ast
std::shared_ptr<Node> g_ast_root;

static int node_line(const std::shared_ptr<Node> &node)
{
    if (!node)
        return yylineno;
    if (auto num = std::dynamic_pointer_cast<NumberNode>(node))
        return num->tok.line;
    if (auto id = std::dynamic_pointer_cast<IdentifierNode>(node))
        return id->tok.line;
    if (auto bin = std::dynamic_pointer_cast<BinOpNode>(node))
        return bin->op_tok.line;
    if (auto assign = std::dynamic_pointer_cast<Assignment>(node))
        return assign->identifier.line;
    return yylineno;
}

// the scanner returns arithmetic operators as bare characters without setting yylval,
// so the operator token is built here instead of being read from $2.
static std::shared_ptr<Node> make_binop(const std::shared_ptr<Node> &left, const char *op, const std::shared_ptr<Node> &right)
{
    auto bin = std::make_shared<BinOpNode>();
    bin->left = left;
    bin->op_tok = Token{TokenType::Arth, op, node_line(left)};
    bin->right = right;
    return bin;
}
%}

/* 2. bison declarations */

// semanticvalue carries the token or ast value of a grammar symbol.
%code requires {
    #include <memory>
    #include <vector>
    #include "ast.hpp"
    #include "tokens.hpp"

    struct SemanticValue {
        std::shared_ptr<Node> node;
        std::shared_ptr<Condition> condition;
        std::vector<Token> token_list;
        Token token;
    };
}

// bison marks a custom api.value.type as trivial and would memcpy the value stack when it grows,
// which corrupts the shared_ptr and vector members. without the flag the stack never relocates
// and overflowing it reports "memory exhausted" instead, so start it deep enough to matter rarely.
%code {
    #undef YYSTYPE_IS_TRIVIAL
    #define YYINITDEPTH 1000
}

%define api.value.type {SemanticValue}
%define parse.error verbose

// tokens that carry additional data use yylval.token from the scanner.
%token T_INTLIT "integer" T_VAR "identifier" T_COMPARISON "comparison operator" T_STRING "string literal"

// keep these token declarations compatible with the provided scanner.
%token T_IF "keyword if" T_ELSE "keyword else" T_WHILE "keyword while" T_INT "keyword int"
%token T_STRINGKW "keyword string" T_PRINT "keyword print" T_PRINTS "keyword prints"
%token T_ASSIGN "assignment operator"
%token T_LPAREN "opening parenthesis" T_RPAREN "closing parenthesis"
%token T_LBRACE "opening brace" T_RBRACE "closing brace" T_SEMICOLON "semicolon" T_END

// the top-level rule to start parsing
%start program

%%
/* 3. grammar rules */

// the 'program' rule waits for all statements and an end token or eof.
// $1 refers to the value of 'statements'. $$ is the value of 'program'.
program
    : statements T_END
    {
        g_ast_root = $1.node; // save the completed ast
    }
    | statements
    {
        g_ast_root = $1.node; // save the completed ast (eof case)
    }
    ;

// combine statements in source order.
statements
    : %empty
    {
        $$.node = nullptr; // base case: no statements
    }
    | statements statement
    {
        auto st = std::make_shared<Statement>();
        st->left = $1.node;  // the previous statements
        st->right = $2.node; // the new statement
        $$.node = st;        // pass the combined list up
    }
    ;

statement
    : if_statement    { $$.node = $1.node; }
    | while_statement { $$.node = $1.node; }
    | declarations    { $$.node = $1.node; }
    | assignment      { $$.node = $1.node; }
    | printing        { $$.node = $1.node; }
    | T_LBRACE statements T_RBRACE // for nested blocks
    {
        $$.node = $2.node;
    }
    ;

// --- expression parsing (expr, term, factor) ---

expr
    : term
    {
        $$.node = $1.node;
    }
    | expr '+' term  // $1 is 'expr', $2 is '+', $3 is 'term'
    {
        $$.node = make_binop($1.node, "+", $3.node);
    }
    | expr '-' term
    {
        $$.node = make_binop($1.node, "-", $3.node);
    }
    ;

term
    : factor
    {
        $$.node = $1.node;
    }
    | term '*' factor
    {
        $$.node = make_binop($1.node, "*", $3.node);
    }
    | term '/' factor
    {
        $$.node = make_binop($1.node, "/", $3.node);
    }
    ;

factor
    : T_INTLIT
    {
        // $1.token is the integer token supplied by the scanner.
        $$.node = std::make_shared<NumberNode>($1.token);
    }
    | T_VAR
    {
        $$.node = std::make_shared<IdentifierNode>($1.token);
    }
    | T_LPAREN expr T_RPAREN
    {
        $$.node = $2.node;
    }
    ;

// --- other statements ---

assignment
    : T_VAR T_ASSIGN expr T_SEMICOLON
    {
        auto assign = std::make_shared<Assignment>();
        assign->identifier = $1.token;
        assign->expression = $3.node;
        $$.node = assign;
    }
    ;

if_statement
    : T_IF T_LPAREN condition T_RPAREN T_LBRACE statements T_RBRACE
    {
        auto if_st = std::make_shared<IfStatement>();
        if_st->if_condition = $3.condition;
        if_st->if_body = $6.node;
        $$.node = if_st;
    }
    | T_IF T_LPAREN condition T_RPAREN T_LBRACE statements T_RBRACE T_ELSE T_LBRACE statements T_RBRACE
    {
        auto if_st = std::make_shared<IfStatement>();
        if_st->if_condition = $3.condition;
        if_st->if_body = $6.node;
        if_st->else_body = $10.node;
        $$.node = if_st;
    }
    ;

condition
    : expr T_COMPARISON expr
    {
        auto cond = std::make_shared<Condition>();
        cond->left_expression = $1.node;
        cond->comparison = $2.token;
        cond->right_expression = $3.node;
        $$.condition = cond;
    }
    ;

while_statement
    : T_WHILE T_LPAREN condition T_RPAREN T_LBRACE statements T_RBRACE
    {
        auto loop = std::make_shared<WhileStatement>();
        loop->condition = $3.condition;
        loop->body = $6.node;
        $$.node = loop;
    }
    ;

printing
    : T_PRINT T_LPAREN expr T_RPAREN T_SEMICOLON
    {
        auto print = std::make_shared<PrintStatement>();
        print->type = "int";
        print->intExpr = $3.node;
        $$.node = print;
    }
    | T_PRINTS T_LPAREN T_STRING T_RPAREN T_SEMICOLON
    {
        auto print = std::make_shared<PrintStatement>();
        print->type = "string";
        print->strValue = $3.token.value;
        $$.node = print;
    }
    ;

declarations
    : T_INT identifier_list T_SEMICOLON
    {
        auto decl = std::make_shared<Declaration>();
        decl->declaration_type = Token{TokenType::Int, "int", $2.token_list.front().line};
        decl->identifiers = $2.token_list;
        $$.node = decl;
    }
    | T_INT T_VAR T_ASSIGN expr T_SEMICOLON
    {
        // working example: int a = 3;
        // the existing ast stores declaration and assignment separately.
        auto decl = std::make_shared<Declaration>();
        decl->declaration_type = Token{TokenType::Int, "int", $2.token.line};
        decl->identifiers.push_back($2.token);

        auto assign = std::make_shared<Assignment>();
        assign->identifier = $2.token;
        assign->expression = $4.node;

        auto sequence = std::make_shared<Statement>();
        sequence->left = decl;
        sequence->right = assign;
        $$.node = sequence;
    }
    | T_STRINGKW identifier_list T_SEMICOLON
    {
        auto decl = std::make_shared<Declaration>();
        decl->declaration_type = Token{TokenType::StringKw, "string", $2.token_list.front().line};
        decl->identifiers = $2.token_list;
        $$.node = decl;
    }
    ;

identifier_list
    : T_VAR
    {
        $$.token_list = {$1.token};
    }
    | identifier_list ',' T_VAR
    {
        $$.token_list = $1.token_list;
        $$.token_list.push_back($3.token);
    }
    ;

%%
/* 4. epilogue */

// bison calls this function on a syntax error.
void yyerror(const char *s) {
    std::string error_msg = "line " + std::to_string(yylineno) + ": " + s;
    // top level statements may end anywhere, so eof is only rejected inside an unfinished construct.
    if (yychar == YYEOF)
        error_msg += " (unclosed block or incomplete statement)";
    else if (yytext && *yytext)
        error_msg += " (near \"" + std::string(yytext) + "\")";
    throw std::runtime_error(error_msg);
}
