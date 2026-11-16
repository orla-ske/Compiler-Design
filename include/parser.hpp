#pragma once
#include <memory>
#include <string>
#include "tokens.hpp"
#include "ast.hpp"

// recursive descent parser, one method per grammar rule
class Parser
{
public:
    explicit Parser(TokenArray tokens);
    std::shared_ptr<Node> get_root();

private:
    // token helpers
    const Token &cur() const { return tokens.current(); }
    bool at(TokenType t) const { return tokens.current().type == t; }
    bool accept(TokenType t);
    Token expect(TokenType t, const std::string &what);
    [[noreturn]] void error(const std::string &message) const;

    // statements
    std::shared_ptr<Node> statement();
    std::shared_ptr<Block> block(const std::string &context);
    std::shared_ptr<Declaration> declaration_body();
    std::shared_ptr<VarDecl> init_declarator();
    std::shared_ptr<Node> initializer();
    std::shared_ptr<Node> simple_statement();
    std::shared_ptr<Node> lvalue();
    std::shared_ptr<Node> if_statement();
    std::shared_ptr<Node> while_statement();
    std::shared_ptr<Node> do_while_statement();
    std::shared_ptr<Node> for_statement();
    std::shared_ptr<Node> printing();
    std::shared_ptr<Node> read_statement();

    // expressions, lowest to highest precedence
    std::shared_ptr<Node> expr();
    std::shared_ptr<Node> conditional();
    std::shared_ptr<Node> logical_or();
    std::shared_ptr<Node> logical_and();
    std::shared_ptr<Node> equality();
    std::shared_ptr<Node> relational();
    std::shared_ptr<Node> bit_or();
    std::shared_ptr<Node> bit_xor();
    std::shared_ptr<Node> bit_and();
    std::shared_ptr<Node> shift();
    std::shared_ptr<Node> additive();
    std::shared_ptr<Node> term();
    std::shared_ptr<Node> unary();
    std::shared_ptr<Node> power();
    std::shared_ptr<Node> factor();

private:
    TokenArray tokens;
};
