#pragma once
#include <string>
#include <unordered_map>
#include <vector>
#include "ast.hpp"

enum class Type { Int, Bool, Error };

struct Symbol
{
    Type type;
    bool is_const;
    int64_t array_size; // -1 when not an array
    int line;
};

// checks the rules a grammar cannot express: scopes, types, const, loops
class SemanticAnalyzer
{
public:
    std::vector<std::string> check(const Node &root);

private:
    void statement(const Node &n);
    void block(const Block &b, bool new_scope);
    void declaration(const Declaration &d);
    void assignment(const Assignment &a);
    void condition(const Node &cond, const std::string &where);
    Type expression(const Node &n);
    Type lvalue(const Node &n, bool must_be_mutable);

    const Symbol *lookup(const std::string &name) const;
    void error(int line, const std::string &message);

    std::vector<std::unordered_map<std::string, Symbol>> scopes;
    std::vector<std::string> errors;
    int loop_depth{0};
};
