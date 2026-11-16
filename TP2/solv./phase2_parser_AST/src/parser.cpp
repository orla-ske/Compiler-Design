#include "parser.hpp"
#include <initializer_list>
#include <stdexcept>

static bool is_keyword(TokenType t) { return t >= TokenType::Int && t <= TokenType::Read; }

static bool is_assign_op(TokenType t) { return t >= TokenType::Assign && t <= TokenType::ShrAssign; }

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

Parser::Parser(TokenArray tokens) : tokens(std::move(tokens))
{
    this->tokens.appendEndIfMissing();
}

/* ---------- token helpers ---------- */

void Parser::error(const std::string &message) const
{
    throw std::runtime_error("syntax error, line " + std::to_string(cur().line) + ": " + message);
}

bool Parser::accept(TokenType t)
{
    if (!at(t)) return false;
    tokens.next();
    return true;
}

Token Parser::expect(TokenType t, const std::string &what)
{
    if (!at(t))
    {
        std::string msg = "expected " + what + ", got " + describe(cur());
        if (is_keyword(cur().type)) msg += " (reserved keyword)";
        if (at(TokenType::Assign) && t == TokenType::RParen) msg += ", use '==' to compare";

        // a missing ';' belongs to the previous line
        int line = cur().line;
        if (t == TokenType::Semicolon && tokens.pos > 0) line = tokens.tokens[tokens.pos - 1].line;
        throw std::runtime_error("syntax error, line " + std::to_string(line) + ": " + msg);
    }
    Token tok = cur();
    tokens.next();
    return tok;
}

/* ---------- program and statements ---------- */

std::shared_ptr<Node> Parser::get_root()
{
    auto program = make_node<Block>(1);
    program->is_program = true;
    while (!at(TokenType::End))
        program->statements.push_back(statement());
    return program;
}

std::shared_ptr<Node> Parser::statement()
{
    switch (cur().type)
    {
    case TokenType::Const:
    case TokenType::Int:
    case TokenType::Bool:
    {
        auto decl = declaration_body();
        expect(TokenType::Semicolon, "';' after the declaration");
        return decl;
    }
    case TokenType::If:       return if_statement();
    case TokenType::While:    return while_statement();
    case TokenType::Do:       return do_while_statement();
    case TokenType::For:      return for_statement();
    case TokenType::Print:
    case TokenType::Prints:   return printing();
    case TokenType::Read:     return read_statement();
    case TokenType::LBrace:   return block("");
    case TokenType::Break:
    case TokenType::Continue:
    {
        int line = cur().line;
        bool is_break = at(TokenType::Break);
        tokens.next();
        expect(TokenType::Semicolon, std::string("';' after '") + (is_break ? "break" : "continue") + "'");
        if (is_break) return make_node<BreakStatement>(line);
        return make_node<ContinueStatement>(line);
    }
    case TokenType::Identifier:
    case TokenType::Increment:
    case TokenType::Decrement:
    {
        auto s = simple_statement();
        expect(TokenType::Semicolon, "';' after the statement");
        return s;
    }
    case TokenType::RBrace:
        error("unmatched '}'");
    case TokenType::Else:
        error("'else' without a matching 'if'");
    default:
        error("unexpected " + describe(cur()) + " at the start of a statement");
    }
}

std::shared_ptr<Block> Parser::block(const std::string &context)
{
    std::string what = context.empty() ? "'{'" : "'{' " + context + " (braces are mandatory)";
    int open_line = expect(TokenType::LBrace, what).line;
    auto b = make_node<Block>(open_line);
    while (!at(TokenType::RBrace))
    {
        if (at(TokenType::End))
            error("missing '}' to close the block opened at line " + std::to_string(open_line));
        b->statements.push_back(statement());
    }
    tokens.next();
    return b;
}

std::shared_ptr<Declaration> Parser::declaration_body()
{
    auto decl = make_node<Declaration>(cur().line);
    decl->is_const = accept(TokenType::Const);
    if (!at(TokenType::Int) && !at(TokenType::Bool))
        error("expected a type ('int' or 'bool'), got " + describe(cur()));
    decl->type = cur().value;
    tokens.next();

    decl->vars.push_back(init_declarator());
    while (accept(TokenType::Comma))
        decl->vars.push_back(init_declarator());
    return decl;
}

std::shared_ptr<VarDecl> Parser::init_declarator()
{
    Token name = expect(TokenType::Identifier, "a variable name");
    auto var = make_node<VarDecl>(name.line);
    var->name = name.value;

    if (accept(TokenType::LBracket))
    {
        if (!at(TokenType::IntLit))
            error("array size must be an integer literal, got " + describe(cur()));
        parse_int_literal(cur().value, var->array_size);
        tokens.next();
        expect(TokenType::RBracket, "']' after the array size");
    }
    if (accept(TokenType::Assign))
        var->init = initializer();
    return var;
}

std::shared_ptr<Node> Parser::initializer()
{
    if (!at(TokenType::LBrace))
        return expr();

    auto list = make_node<InitList>(cur().line);
    tokens.next();
    if (at(TokenType::RBrace))
        error("an initializer list needs at least one value");
    list->values.push_back(expr());
    while (accept(TokenType::Comma))
        list->values.push_back(expr());
    expect(TokenType::RBrace, "',' or '}' in the initializer list");
    return list;
}

std::shared_ptr<Node> Parser::lvalue()
{
    Token name = expect(TokenType::Identifier, "a variable name");
    if (!accept(TokenType::LBracket))
        return std::make_shared<IdentifierNode>(name);

    auto access = make_node<ArrayAccessNode>(name.line);
    access->name = name.value;
    access->index = expr();
    expect(TokenType::RBracket, "']' after the array index");
    return access;
}

std::shared_ptr<Node> Parser::simple_statement()
{
    // prefix form: ++x or --x
    if (at(TokenType::Increment) || at(TokenType::Decrement))
    {
        auto inc = make_node<IncDec>(cur().line);
        inc->op_tok = cur();
        inc->prefix = true;
        tokens.next();
        inc->target = lvalue();
        return inc;
    }

    auto target = lvalue();
    if (at(TokenType::Increment) || at(TokenType::Decrement))
    {
        auto inc = make_node<IncDec>(cur().line);
        inc->op_tok = cur();
        inc->target = target;
        tokens.next();
        return inc;
    }
    if (!is_assign_op(cur().type))
        error("expected an assignment operator, '++' or '--', got " + describe(cur()));

    auto a = make_node<Assignment>(cur().line);
    a->op_tok = cur();
    a->target = target;
    tokens.next();
    a->expression = expr();
    return a;
}

std::shared_ptr<Node> Parser::if_statement()
{
    auto node = make_node<IfStatement>(cur().line);
    tokens.next();
    expect(TokenType::LParen, "'(' after 'if'");
    node->cond = expr();
    expect(TokenType::RParen, "')' after the if condition");
    node->then_block = block("after the if condition");

    if (accept(TokenType::Else))
        node->else_branch = at(TokenType::If) ? if_statement() : block("after 'else'");
    return node;
}

std::shared_ptr<Node> Parser::while_statement()
{
    auto node = make_node<WhileStatement>(cur().line);
    tokens.next();
    expect(TokenType::LParen, "'(' after 'while'");
    node->cond = expr();
    expect(TokenType::RParen, "')' after the while condition");
    node->body = block("after the while condition");
    return node;
}

std::shared_ptr<Node> Parser::do_while_statement()
{
    auto node = make_node<DoWhileStatement>(cur().line);
    tokens.next();
    node->body = block("after 'do'");
    expect(TokenType::While, "'while' after the do block");
    expect(TokenType::LParen, "'(' after 'while'");
    node->cond = expr();
    expect(TokenType::RParen, "')' after the do-while condition");
    expect(TokenType::Semicolon, "';' after the do-while condition");
    return node;
}

std::shared_ptr<Node> Parser::for_statement()
{
    auto node = make_node<ForStatement>(cur().line);
    tokens.next();
    expect(TokenType::LParen, "'(' after 'for'");

    if (at(TokenType::Const) || at(TokenType::Int) || at(TokenType::Bool))
        node->init = declaration_body();
    else if (!at(TokenType::Semicolon))
        node->init = simple_statement();
    expect(TokenType::Semicolon, "';' after the for initialisation");

    if (!at(TokenType::Semicolon))
        node->cond = expr();
    expect(TokenType::Semicolon, "';' after the for condition");

    if (!at(TokenType::RParen))
        node->update = simple_statement();
    expect(TokenType::RParen, "')' to close the for header");

    node->body = block("after the for header");
    return node;
}

std::shared_ptr<Node> Parser::printing()
{
    auto node = make_node<PrintStatement>(cur().line);
    node->is_prints = at(TokenType::Prints);
    tokens.next();
    expect(TokenType::LParen, node->is_prints ? "'(' after 'prints'" : "'(' after 'print'");

    if (node->is_prints)
    {
        Token s = expect(TokenType::String, "a string literal in prints");
        auto str = make_node<StringNode>(s.line);
        str->value = s.value;
        node->args.push_back(str);
    }
    else
    {
        do
        {
            if (at(TokenType::String))
            {
                auto str = make_node<StringNode>(cur().line);
                str->value = cur().value;
                tokens.next();
                node->args.push_back(str);
            }
            else
                node->args.push_back(expr());
        } while (accept(TokenType::Comma));
    }
    expect(TokenType::RParen, "')' to close the print arguments");
    expect(TokenType::Semicolon, "';' after the print statement");
    return node;
}

std::shared_ptr<Node> Parser::read_statement()
{
    auto node = make_node<ReadStatement>(cur().line);
    tokens.next();
    expect(TokenType::LParen, "'(' after 'read'");
    node->targets.push_back(lvalue());
    while (accept(TokenType::Comma))
        node->targets.push_back(lvalue());
    expect(TokenType::RParen, "')' to close the read arguments");
    expect(TokenType::Semicolon, "';' after the read statement");
    return node;
}

/* ---------- expressions ---------- */

std::shared_ptr<Node> Parser::expr()
{
    return conditional();
}

std::shared_ptr<Node> Parser::conditional()
{
    auto cond = logical_or();
    if (!at(TokenType::Question))
        return cond;

    auto node = make_node<TernaryNode>(cur().line);
    tokens.next();
    node->cond = cond;
    node->then_expr = expr();
    expect(TokenType::Colon, "':' in the conditional expression");
    node->else_expr = conditional(); // right recursion, right associative
    return node;
}

std::shared_ptr<Node> Parser::logical_or()
{
    auto left = logical_and();
    while (at(TokenType::Or))
    {
        Token op = cur();
        tokens.next();
        left = make_binop(left, op, logical_and());
    }
    return left;
}

std::shared_ptr<Node> Parser::logical_and()
{
    auto left = equality();
    while (at(TokenType::And))
    {
        Token op = cur();
        tokens.next();
        left = make_binop(left, op, equality());
    }
    return left;
}

std::shared_ptr<Node> Parser::equality()
{
    auto left = relational();
    if (at(TokenType::Eq) || at(TokenType::Neq))
    {
        Token op = cur();
        tokens.next();
        left = make_binop(left, op, relational());
        if (at(TokenType::Eq) || at(TokenType::Neq))
            error("comparisons cannot be chained, combine them with && or ||");
    }
    return left;
}

std::shared_ptr<Node> Parser::relational()
{
    auto is_rel = [this] {
        return at(TokenType::Lt) || at(TokenType::Le) || at(TokenType::Gt) || at(TokenType::Ge);
    };
    auto left = bit_or();
    if (is_rel())
    {
        Token op = cur();
        tokens.next();
        left = make_binop(left, op, bit_or());
        if (is_rel())
            error("comparisons cannot be chained, write a < b && b < c");
    }
    return left;
}

std::shared_ptr<Node> Parser::bit_or()
{
    auto left = bit_xor();
    while (at(TokenType::BitOr))
    {
        Token op = cur();
        tokens.next();
        left = make_binop(left, op, bit_xor());
    }
    return left;
}

std::shared_ptr<Node> Parser::bit_xor()
{
    auto left = bit_and();
    while (at(TokenType::BitXor))
    {
        Token op = cur();
        tokens.next();
        left = make_binop(left, op, bit_and());
    }
    return left;
}

std::shared_ptr<Node> Parser::bit_and()
{
    auto left = shift();
    while (at(TokenType::BitAnd))
    {
        Token op = cur();
        tokens.next();
        left = make_binop(left, op, shift());
    }
    return left;
}

std::shared_ptr<Node> Parser::shift()
{
    auto left = additive();
    while (at(TokenType::Shl) || at(TokenType::Shr))
    {
        Token op = cur();
        tokens.next();
        left = make_binop(left, op, additive());
    }
    return left;
}

std::shared_ptr<Node> Parser::additive()
{
    auto left = term();
    while (at(TokenType::Plus) || at(TokenType::Minus))
    {
        Token op = cur();
        tokens.next();
        left = make_binop(left, op, term());
    }
    return left;
}

std::shared_ptr<Node> Parser::term()
{
    auto left = unary();
    while (at(TokenType::Star) || at(TokenType::Slash) || at(TokenType::Percent))
    {
        Token op = cur();
        tokens.next();
        left = make_binop(left, op, unary());
    }
    return left;
}

std::shared_ptr<Node> Parser::unary()
{
    if (at(TokenType::Minus) || at(TokenType::Not) || at(TokenType::BitNot))
    {
        auto node = make_node<UnaryOpNode>(cur().line);
        node->op_tok = cur();
        tokens.next();
        node->operand = unary();
        return node;
    }
    return power();
}

std::shared_ptr<Node> Parser::power()
{
    auto base = factor();
    if (!at(TokenType::Power))
        return base;
    Token op = cur();
    tokens.next();
    return make_binop(base, op, unary()); // right associative via unary
}

std::shared_ptr<Node> Parser::factor()
{
    const Token tok = cur();
    switch (tok.type)
    {
    case TokenType::IntLit:
        tokens.next();
        return std::make_shared<NumberNode>(tok);
    case TokenType::True:
    case TokenType::False:
    {
        auto b = make_node<BoolNode>(tok.line);
        b->value = tok.type == TokenType::True;
        tokens.next();
        return b;
    }
    case TokenType::Identifier:
    {
        tokens.next();
        if (!accept(TokenType::LBracket))
            return std::make_shared<IdentifierNode>(tok);
        auto access = make_node<ArrayAccessNode>(tok.line);
        access->name = tok.value;
        access->index = expr();
        expect(TokenType::RBracket, "']' after the array index");
        return access;
    }
    case TokenType::LParen:
    {
        tokens.next();
        auto e = expr();
        expect(TokenType::RParen, "')' to close the parenthesis");
        return e;
    }
    case TokenType::String:
        error("a string can only be used directly in print or prints");
    case TokenType::Increment:
    case TokenType::Decrement:
        error("'" + tok.value + "' is a statement and cannot be used inside an expression");
    default:
        error("expected an expression, got " + describe(tok));
    }
}
