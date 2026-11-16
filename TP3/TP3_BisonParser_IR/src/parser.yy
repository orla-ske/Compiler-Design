/*
 * Bison grammar for the language.
 *
 * It builds exactly the same AST (include/ast.hpp) as the hand-written
 * recursive-descent parser in parser.cpp, so the semantic analyser and the
 * AST printer work with either parser. Run it with: ./compiler --bison file.txt
 *
 * The tokens come from the Flex scanner (scanner.l), which has already turned
 * the whole source into a std::vector<Token>. bblex() below hands those tokens
 * to Bison one at a time.
 *
 * Needs Bison >= 3.6 (for %define parse.error detailed).
 */

/* 1. BISON DECLARATIONS */

// Prefix every generated name with bb (bbparse, bblex, bberror, bblval) so it
// cannot clash with yylex / yylineno from the Flex scanner.
%define api.prefix {bb}
%define parse.error detailed
%define api.value.type {SemanticValue}

// The grammar must stay free of shift/reduce and reduce/reduce conflicts.
%expect 0

// SemanticValue carries the token or AST value of a grammar symbol.
%code requires {
    #include <memory>
    #include <vector>
    #include "ast.hpp"
    #include "tokens.hpp"

    struct SemanticValue
    {
        NodePtr node;              // AST node built by a rule
        std::vector<NodePtr> list; // statements, print arguments, read targets...
        Token token{TokenType::End, "", 0}; // token read by the scanner
    };
}

// %code (unlike %{ %}) is emitted after SemanticValue, so it can use the AST types.
%code {
#include <stdexcept>
#include <string>

int bblex();
void bberror(const char *msg);

// SemanticValue is not trivially copyable, so in C++ Bison cannot grow its
// stack. Start with a large one instead of the default 200 entries.
#define YYINITDEPTH 2000

static const std::vector<Token> *g_tokens = nullptr; // scanner output
static size_t g_pos = 0;          // next token to hand to Bison
static int g_line = 1;            // line of the last token read (the lookahead)
static int g_prev_line = 1;       // line of the token before it
static std::string g_error;       // syntax error message, set by bberror
static NodePtr g_root;            // finished AST

template <typename T>
static std::shared_ptr<T> make_node(int line)
{
    auto n = std::make_shared<T>();
    n->line = line;
    return n;
}

static NodePtr make_binop(NodePtr left, const Token &op, NodePtr right)
{
    auto bin = make_node<BinOpNode>(op.line);
    bin->left = std::move(left);
    bin->op_tok = op;
    bin->right = std::move(right);
    return bin;
}

static NodePtr make_unary(const Token &op, NodePtr operand)
{
    auto u = make_node<UnaryOpNode>(op.line);
    u->op_tok = op;
    u->operand = std::move(operand);
    return u;
}

static NodePtr make_if(const Token &kw, NodePtr cond, NodePtr then_block, NodePtr else_branch)
{
    auto n = make_node<IfStatement>(kw.line);
    n->cond = std::move(cond);
    n->then_block = std::move(then_block);
    n->else_branch = std::move(else_branch);
    return n;
}

static NodePtr make_decl(const Token &first, bool is_const, const Token &type)
{
    auto d = make_node<Declaration>(first.line);
    d->is_const = is_const;
    d->type = type.value;
    return d;
}

static NodePtr make_var(const Token &name, const Token *size, NodePtr init)
{
    auto v = make_node<VarDecl>(name.line);
    v->name = name.value;
    if (size) parse_int_literal(size->value, v->array_size);
    v->init = std::move(init);
    return v;
}

static NodePtr make_incdec(const Token &op, NodePtr target, bool prefix)
{
    auto n = make_node<IncDec>(op.line);
    n->op_tok = op;
    n->target = std::move(target);
    n->prefix = prefix;
    return n;
}

static NodePtr make_string(const Token &s)
{
    auto n = make_node<StringNode>(s.line);
    n->value = s.value;
    return n;
}
}

/* Token kinds. The quoted alias is what appears in syntax error messages. */

%token T_END 0 "end of file"

// keywords
%token T_INT "'int'" T_BOOL "'bool'" T_CONST "'const'" T_TRUE "'true'" T_FALSE "'false'"
%token T_IF "'if'" T_ELSE "'else'" T_WHILE "'while'" T_DO "'do'" T_FOR "'for'"
%token T_BREAK "'break'" T_CONTINUE "'continue'"
%token T_PRINT "'print'" T_PRINTS "'prints'" T_READ "'read'"

// names and literals
%token T_IDENT "identifier" T_INTLIT "number" T_STRING "string"

// assignment
%token T_ASSIGN "'='" T_PLUS_ASSIGN "'+='" T_MINUS_ASSIGN "'-='" T_STAR_ASSIGN "'*='"
%token T_SLASH_ASSIGN "'/='" T_PERCENT_ASSIGN "'%='" T_AND_ASSIGN "'&='" T_OR_ASSIGN "'|='"
%token T_XOR_ASSIGN "'^='" T_SHL_ASSIGN "'<<='" T_SHR_ASSIGN "'>>='"
%token T_INC "'++'" T_DEC "'--'"

// operators
%token T_EQ "'=='" T_NEQ "'!='" T_LT "'<'" T_LE "'<='" T_GT "'>'" T_GE "'>='"
%token T_PLUS "'+'" T_MINUS "'-'" T_STAR "'*'" T_SLASH "'/'" T_PERCENT "'%'" T_POW "'**'"
%token T_BITAND "'&'" T_BITOR "'|'" T_BITXOR "'^'" T_BITNOT "'~'" T_SHL "'<<'" T_SHR "'>>'"
%token T_AND "'&&'" T_OR "'||'" T_NOT "'!'"

// punctuation
%token T_LPAREN "'('" T_RPAREN "')'" T_LBRACE "'{'" T_RBRACE "'}'"
%token T_LBRACKET "'['" T_RBRACKET "']'" T_SEMI "';'" T_COMMA "','"
%token T_QUESTION "'?'" T_COLON "':'"

/* Operator precedence, lowest to highest (same as parser.cpp). */
%right    T_QUESTION T_COLON              // a ? b : c
%left     T_OR                            // ||
%left     T_AND                           // &&
%nonassoc T_EQ T_NEQ                      // == !=     (cannot be chained)
%nonassoc T_LT T_LE T_GT T_GE             // < <= > >= (cannot be chained)
%left     T_BITOR                         // |
%left     T_BITXOR                        // ^
%left     T_BITAND                        // &
%left     T_SHL T_SHR                     // << >>
%left     T_PLUS T_MINUS                  // + -
%left     T_STAR T_SLASH T_PERCENT        // * / %
%precedence UNARY                         // -x !x ~x
%right    T_POW                           // **  (-a ** b is -(a ** b))

%start program

%%
/* 2. GRAMMAR RULES */

// Before each action Bison sets $$ to a copy of $1. Rules with an empty
// right-hand side therefore reset $$ themselves.

program
    : stmt_list
    {
        auto p = make_node<Block>(1);
        p->is_program = true;
        p->statements = std::move($1.list);
        g_root = p;
    }
    ;

stmt_list
    : %empty               { $$ = SemanticValue(); }
    | stmt_list statement  { $$.list.push_back($2.node); }
    ;

statement
    : declaration T_SEMI   { $$.node = $1.node; }
    | simple T_SEMI        { $$.node = $1.node; }
    | if_statement         { $$.node = $1.node; }
    | block                { $$.node = $1.node; }
    | T_WHILE T_LPAREN expr T_RPAREN block
    {
        auto n = make_node<WhileStatement>($1.token.line);
        n->cond = $3.node;
        n->body = $5.node;
        $$.node = n;
    }
    | T_DO block T_WHILE T_LPAREN expr T_RPAREN T_SEMI
    {
        auto n = make_node<DoWhileStatement>($1.token.line);
        n->body = $2.node;
        n->cond = $5.node;
        $$.node = n;
    }
    | T_FOR T_LPAREN for_init T_SEMI opt_expr T_SEMI opt_simple T_RPAREN block
    {
        auto n = make_node<ForStatement>($1.token.line);
        n->init = $3.node;
        n->cond = $5.node;
        n->update = $7.node;
        n->body = $9.node;
        $$.node = n;
    }
    | T_PRINT T_LPAREN print_args T_RPAREN T_SEMI
    {
        auto n = make_node<PrintStatement>($1.token.line);
        n->args = std::move($3.list);
        $$.node = n;
    }
    | T_PRINTS T_LPAREN T_STRING T_RPAREN T_SEMI
    {
        auto n = make_node<PrintStatement>($1.token.line);
        n->is_prints = true;
        n->args.push_back(make_string($3.token));
        $$.node = n;
    }
    | T_READ T_LPAREN lvalue_list T_RPAREN T_SEMI
    {
        auto n = make_node<ReadStatement>($1.token.line);
        n->targets = std::move($3.list);
        $$.node = n;
    }
    | T_BREAK T_SEMI       { $$.node = make_node<BreakStatement>($1.token.line); }
    | T_CONTINUE T_SEMI    { $$.node = make_node<ContinueStatement>($1.token.line); }
    ;

// Braces are mandatory around if / while / do / for bodies.
block
    : T_LBRACE stmt_list T_RBRACE
    {
        auto b = make_node<Block>($1.token.line);
        b->statements = std::move($2.list);
        $$.node = b;
    }
    ;

if_statement
    : T_IF T_LPAREN expr T_RPAREN block
    {
        $$.node = make_if($1.token, $3.node, $5.node, nullptr);
    }
    | T_IF T_LPAREN expr T_RPAREN block T_ELSE block
    {
        $$.node = make_if($1.token, $3.node, $5.node, $7.node);
    }
    | T_IF T_LPAREN expr T_RPAREN block T_ELSE if_statement // else if
    {
        $$.node = make_if($1.token, $3.node, $5.node, $7.node);
    }
    ;

// --- Declarations: [const] int|bool a, b[3] = {1, 2}, c = 4 ---

declaration
    : type_spec init_declarator
    {
        std::static_pointer_cast<Declaration>($1.node)->vars.push_back(
            std::static_pointer_cast<VarDecl>($2.node));
        $$.node = $1.node;
    }
    | declaration T_COMMA init_declarator
    {
        std::static_pointer_cast<Declaration>($1.node)->vars.push_back(
            std::static_pointer_cast<VarDecl>($3.node));
        $$.node = $1.node;
    }
    ;

type_spec
    : T_INT            { $$.node = make_decl($1.token, false, $1.token); }
    | T_BOOL           { $$.node = make_decl($1.token, false, $1.token); }
    | T_CONST T_INT    { $$.node = make_decl($1.token, true, $2.token); }
    | T_CONST T_BOOL   { $$.node = make_decl($1.token, true, $2.token); }
    ;

init_declarator
    : T_IDENT                                       { $$.node = make_var($1.token, nullptr, nullptr); }
    | T_IDENT T_ASSIGN initializer                  { $$.node = make_var($1.token, nullptr, $3.node); }
    | T_IDENT T_LBRACKET T_INTLIT T_RBRACKET        { $$.node = make_var($1.token, &$3.token, nullptr); }
    | T_IDENT T_LBRACKET T_INTLIT T_RBRACKET T_ASSIGN initializer
                                                    { $$.node = make_var($1.token, &$3.token, $6.node); }
    ;

initializer
    : expr  { $$.node = $1.node; }
    | T_LBRACE expr_list T_RBRACE
    {
        auto l = make_node<InitList>($1.token.line);
        l->values = std::move($2.list);
        $$.node = l;
    }
    ;

expr_list
    : expr                       { $$ = SemanticValue(); $$.list.push_back($1.node); }
    | expr_list T_COMMA expr     { $$.list.push_back($3.node); }
    ;

// --- Simple statements: assignment, ++ and -- (also used in for headers) ---

simple
    : lvalue assign_op expr
    {
        auto a = make_node<Assignment>($2.token.line);
        a->target = $1.node;
        a->op_tok = $2.token;
        a->expression = $3.node;
        $$.node = a;
    }
    | lvalue incdec_op   { $$.node = make_incdec($2.token, $1.node, false); }
    | incdec_op lvalue   { $$.node = make_incdec($1.token, $2.node, true); }
    ;

assign_op
    : T_ASSIGN | T_PLUS_ASSIGN | T_MINUS_ASSIGN | T_STAR_ASSIGN | T_SLASH_ASSIGN
    | T_PERCENT_ASSIGN | T_AND_ASSIGN | T_OR_ASSIGN | T_XOR_ASSIGN
    | T_SHL_ASSIGN | T_SHR_ASSIGN
    ; // default action $$ = $1 keeps the operator token

incdec_op
    : T_INC | T_DEC
    ;

lvalue
    : T_IDENT
    {
        $$.node = std::make_shared<IdentifierNode>($1.token);
    }
    | T_IDENT T_LBRACKET expr T_RBRACKET
    {
        auto a = make_node<ArrayAccessNode>($1.token.line);
        a->name = $1.token.value;
        a->index = $3.node;
        $$.node = a;
    }
    ;

lvalue_list
    : lvalue                         { $$ = SemanticValue(); $$.list.push_back($1.node); }
    | lvalue_list T_COMMA lvalue     { $$.list.push_back($3.node); }
    ;

// --- for (init; cond; update): each part is optional ---

for_init
    : %empty        { $$ = SemanticValue(); }
    | declaration   { $$.node = $1.node; }
    | simple        { $$.node = $1.node; }
    ;

opt_expr
    : %empty  { $$ = SemanticValue(); }
    | expr    { $$.node = $1.node; }
    ;

opt_simple
    : %empty  { $$ = SemanticValue(); }
    | simple  { $$.node = $1.node; }
    ;

// --- print("text", x, "\n"): strings are only allowed as print arguments ---

print_args
    : print_arg                      { $$ = SemanticValue(); $$.list.push_back($1.node); }
    | print_args T_COMMA print_arg   { $$.list.push_back($3.node); }
    ;

print_arg
    : T_STRING  { $$.node = make_string($1.token); }
    | expr      { $$.node = $1.node; }
    ;

// --- Expressions (precedence comes from the declarations above) ---

expr
    : primary                              { $$.node = $1.node; }
    | expr T_QUESTION expr T_COLON expr
    {
        auto t = make_node<TernaryNode>($2.token.line);
        t->cond = $1.node;
        t->then_expr = $3.node;
        t->else_expr = $5.node;
        $$.node = t;
    }
    | expr T_OR expr        { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_AND expr       { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_EQ expr        { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_NEQ expr       { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_LT expr        { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_LE expr        { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_GT expr        { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_GE expr        { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_BITOR expr     { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_BITXOR expr    { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_BITAND expr    { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_SHL expr       { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_SHR expr       { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_PLUS expr      { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_MINUS expr     { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_STAR expr      { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_SLASH expr     { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_PERCENT expr   { $$.node = make_binop($1.node, $2.token, $3.node); }
    | expr T_POW expr       { $$.node = make_binop($1.node, $2.token, $3.node); }
    | T_MINUS expr  %prec UNARY  { $$.node = make_unary($1.token, $2.node); }
    | T_NOT expr    %prec UNARY  { $$.node = make_unary($1.token, $2.node); }
    | T_BITNOT expr %prec UNARY  { $$.node = make_unary($1.token, $2.node); }
    ;

primary
    : T_INTLIT  { $$.node = std::make_shared<NumberNode>($1.token); }
    | T_TRUE
    {
        auto b = make_node<BoolNode>($1.token.line);
        b->value = true;
        $$.node = b;
    }
    | T_FALSE   { $$.node = make_node<BoolNode>($1.token.line); }
    | lvalue    { $$.node = $1.node; }
    | T_LPAREN expr T_RPAREN  { $$.node = $2.node; }
    ;

%%
/* 3. EPILOGUE */

// Maps a scanner TokenType to the Bison token kind declared above.
static int token_kind(TokenType t)
{
    switch (t)
    {
    case TokenType::Int:           return T_INT;
    case TokenType::Bool:          return T_BOOL;
    case TokenType::Const:         return T_CONST;
    case TokenType::True:          return T_TRUE;
    case TokenType::False:         return T_FALSE;
    case TokenType::If:            return T_IF;
    case TokenType::Else:          return T_ELSE;
    case TokenType::While:         return T_WHILE;
    case TokenType::Do:            return T_DO;
    case TokenType::For:           return T_FOR;
    case TokenType::Break:         return T_BREAK;
    case TokenType::Continue:      return T_CONTINUE;
    case TokenType::Print:         return T_PRINT;
    case TokenType::Prints:        return T_PRINTS;
    case TokenType::Read:          return T_READ;
    case TokenType::Identifier:    return T_IDENT;
    case TokenType::IntLit:        return T_INTLIT;
    case TokenType::String:        return T_STRING;
    case TokenType::Assign:        return T_ASSIGN;
    case TokenType::PlusAssign:    return T_PLUS_ASSIGN;
    case TokenType::MinusAssign:   return T_MINUS_ASSIGN;
    case TokenType::StarAssign:    return T_STAR_ASSIGN;
    case TokenType::SlashAssign:   return T_SLASH_ASSIGN;
    case TokenType::PercentAssign: return T_PERCENT_ASSIGN;
    case TokenType::AndAssign:     return T_AND_ASSIGN;
    case TokenType::OrAssign:      return T_OR_ASSIGN;
    case TokenType::XorAssign:     return T_XOR_ASSIGN;
    case TokenType::ShlAssign:     return T_SHL_ASSIGN;
    case TokenType::ShrAssign:     return T_SHR_ASSIGN;
    case TokenType::Increment:     return T_INC;
    case TokenType::Decrement:     return T_DEC;
    case TokenType::Eq:            return T_EQ;
    case TokenType::Neq:           return T_NEQ;
    case TokenType::Lt:            return T_LT;
    case TokenType::Le:            return T_LE;
    case TokenType::Gt:            return T_GT;
    case TokenType::Ge:            return T_GE;
    case TokenType::Plus:          return T_PLUS;
    case TokenType::Minus:         return T_MINUS;
    case TokenType::Star:          return T_STAR;
    case TokenType::Slash:         return T_SLASH;
    case TokenType::Percent:       return T_PERCENT;
    case TokenType::Power:         return T_POW;
    case TokenType::BitAnd:        return T_BITAND;
    case TokenType::BitOr:         return T_BITOR;
    case TokenType::BitXor:        return T_BITXOR;
    case TokenType::BitNot:        return T_BITNOT;
    case TokenType::Shl:           return T_SHL;
    case TokenType::Shr:           return T_SHR;
    case TokenType::And:           return T_AND;
    case TokenType::Or:            return T_OR;
    case TokenType::Not:           return T_NOT;
    case TokenType::LParen:        return T_LPAREN;
    case TokenType::RParen:        return T_RPAREN;
    case TokenType::LBrace:        return T_LBRACE;
    case TokenType::RBrace:        return T_RBRACE;
    case TokenType::LBracket:      return T_LBRACKET;
    case TokenType::RBracket:      return T_RBRACKET;
    case TokenType::Semicolon:     return T_SEMI;
    case TokenType::Comma:         return T_COMMA;
    case TokenType::Question:      return T_QUESTION;
    case TokenType::Colon:         return T_COLON;
    case TokenType::End:           return T_END;
    }
    return T_END;
}

// Bison calls this to get the next token; the token itself goes in bblval.
int bblex()
{
    if (!g_tokens || g_pos >= g_tokens->size())
        return T_END;
    const Token &t = (*g_tokens)[g_pos++];
    g_prev_line = g_line;
    g_line = t.line;
    bblval = SemanticValue();
    bblval.token = t;
    return token_kind(t.type);
}

// Bison calls this on a syntax error. The message is kept and thrown by
// parse_with_bison once bbparse has returned.
void bberror(const char *msg)
{
    std::string m = msg;
    const std::string prefix = "syntax error, ";
    if (m.compare(0, prefix.size(), prefix) == 0)
        m = m.substr(prefix.size());

    // show the value of names, numbers and strings: unexpected identifier 'x'
    if (g_tokens && g_pos > 0)
    {
        const Token &t = (*g_tokens)[g_pos - 1];
        const char *kind = t.type == TokenType::Identifier ? "identifier"
                         : t.type == TokenType::IntLit     ? "number"
                         : t.type == TokenType::String     ? "string"
                                                           : nullptr;
        std::string what = kind ? std::string("unexpected ") + kind : "";
        if (kind && m.compare(0, what.size(), what) == 0)
            m = "unexpected " + describe(t) + m.substr(what.size());
    }

    // a missing ';' belongs to the line before the unexpected token
    int line = m.find("expecting ';'") != std::string::npos ? g_prev_line : g_line;
    g_error = "syntax error, line " + std::to_string(line) + ": " + m;
}

// Entry point used by main.cpp.
std::shared_ptr<Node> parse_with_bison(const std::vector<Token> &tokens)
{
    g_tokens = &tokens;
    g_pos = 0;
    g_line = g_prev_line = 1;
    g_error.clear();
    g_root.reset();

    int status = bbparse();
    g_tokens = nullptr;
    if (status != 0)
        throw std::runtime_error(g_error.empty() ? "syntax error" : g_error);

    NodePtr root = std::move(g_root);
    g_root.reset();
    return root;
}
