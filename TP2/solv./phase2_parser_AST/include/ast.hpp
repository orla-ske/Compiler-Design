#pragma once
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include "tokens.hpp"

struct Node;
using NodePtr = std::shared_ptr<Node>;

// child link, edge names the role (cond, body...)
struct Child
{
    std::string edge;
    const Node *node;
};

struct Node
{
    int line{0};
    virtual ~Node() = default;
    virtual std::string label() const = 0;
    virtual std::vector<Child> children() const { return {}; }
};

// adds a child only when it exists
inline void add(std::vector<Child> &out, const std::string &edge, const NodePtr &n)
{
    if (n) out.push_back({edge, n.get()});
}

/* ---------- expressions ---------- */

struct NumberNode : Node
{
    Token tok;
    int64_t value{0};
    explicit NumberNode(Token t) : tok(std::move(t))
    {
        line = tok.line;
        parse_int_literal(tok.value, value);
    }
    std::string getValue() const { return tok.value; }
    std::string label() const override
    {
        std::string v = std::to_string(value);
        return tok.value == v ? "Number " + v : "Number " + tok.value + " (" + v + ")";
    }
};

struct BoolNode : Node
{
    bool value{false};
    std::string label() const override { return std::string("Bool ") + (value ? "true" : "false"); }
};

struct StringNode : Node
{
    std::string value; // raw text, escapes not decoded
    std::string label() const override { return "String \"" + value + "\""; }
};

struct IdentifierNode : Node
{
    Token tok;
    explicit IdentifierNode(Token t) : tok(std::move(t)) { line = tok.line; }
    std::string getValue() const { return tok.value; }
    std::string label() const override { return "Identifier " + tok.value; }
};

struct ArrayAccessNode : Node
{
    std::string name;
    NodePtr index;
    std::string label() const override { return "ArrayAccess " + name; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "index", index);
        return c;
    }
};

struct UnaryOpNode : Node
{
    Token op_tok;
    NodePtr operand;
    std::string label() const override { return "UnaryOp " + op_tok.value; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "", operand);
        return c;
    }
};

struct BinOpNode : Node
{
    NodePtr left;
    Token op_tok;
    NodePtr right;
    std::string label() const override { return "BinOp " + op_tok.value; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "left", left);
        add(c, "right", right);
        return c;
    }
};

struct TernaryNode : Node
{
    NodePtr cond, then_expr, else_expr;
    std::string label() const override { return "Ternary ?:"; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "cond", cond);
        add(c, "then", then_expr);
        add(c, "else", else_expr);
        return c;
    }
};

/* ---------- statements ---------- */

struct Block : Node
{
    bool is_program{false};
    std::vector<NodePtr> statements;
    std::string label() const override { return is_program ? "Program" : "Block"; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        for (auto &s : statements) add(c, "", s);
        return c;
    }
};

struct InitList : Node
{
    std::vector<NodePtr> values;
    std::string label() const override { return "InitList (" + std::to_string(values.size()) + ")"; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        for (auto &v : values) add(c, "", v);
        return c;
    }
};

struct VarDecl : Node
{
    std::string name;
    int64_t array_size{-1}; // -1 means not an array
    NodePtr init;
    bool is_array() const { return array_size >= 0; }
    std::string label() const override
    {
        return "VarDecl " + name + (is_array() ? "[" + std::to_string(array_size) + "]" : "");
    }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "init", init);
        return c;
    }
};

struct Declaration : Node
{
    bool is_const{false};
    std::string type; // "int" or "bool"
    std::vector<std::shared_ptr<VarDecl>> vars;
    std::string label() const override { return std::string("Declaration ") + (is_const ? "const " : "") + type; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        for (auto &v : vars) add(c, "", v);
        return c;
    }
};

struct Assignment : Node
{
    NodePtr target; // IdentifierNode or ArrayAccessNode
    Token op_tok;
    NodePtr expression;
    std::string label() const override { return "Assign " + op_tok.value; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "target", target);
        add(c, "value", expression);
        return c;
    }
};

struct IncDec : Node
{
    NodePtr target;
    Token op_tok;
    bool prefix{false};
    std::string label() const override { return std::string(prefix ? "IncDec prefix " : "IncDec postfix ") + op_tok.value; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "target", target);
        return c;
    }
};

struct IfStatement : Node
{
    NodePtr cond, then_block, else_branch; // else may be Block or IfStatement
    std::string label() const override { return "If"; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "cond", cond);
        add(c, "then", then_block);
        add(c, "else", else_branch);
        return c;
    }
};

struct WhileStatement : Node
{
    NodePtr cond, body;
    std::string label() const override { return "While"; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "cond", cond);
        add(c, "body", body);
        return c;
    }
};

struct DoWhileStatement : Node
{
    NodePtr body, cond;
    std::string label() const override { return "DoWhile"; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "body", body);
        add(c, "cond", cond);
        return c;
    }
};

struct ForStatement : Node
{
    NodePtr init, cond, update, body; // first three may be null
    std::string label() const override { return "For"; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        add(c, "init", init);
        add(c, "cond", cond);
        add(c, "update", update);
        add(c, "body", body);
        return c;
    }
};

struct BreakStatement : Node
{
    std::string label() const override { return "Break"; }
};

struct ContinueStatement : Node
{
    std::string label() const override { return "Continue"; }
};

struct PrintStatement : Node
{
    bool is_prints{false};
    std::vector<NodePtr> args;
    std::string label() const override { return is_prints ? "Prints" : "Print"; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        for (auto &a : args) add(c, "", a);
        return c;
    }
};

struct ReadStatement : Node
{
    std::vector<NodePtr> targets;
    std::string label() const override { return "Read"; }
    std::vector<Child> children() const override
    {
        std::vector<Child> c;
        for (auto &t : targets) add(c, "", t);
        return c;
    }
};
