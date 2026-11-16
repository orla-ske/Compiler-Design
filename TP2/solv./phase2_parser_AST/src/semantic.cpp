#include "semantic.hpp"

static std::string type_name(Type t) { return t == Type::Int ? "int" : "bool"; }

static std::string a_type(Type t) { return t == Type::Int ? "an int" : "a bool"; }

// error type means already reported, stay silent
static bool known(Type t) { return t != Type::Error; }

static bool is_zero_literal(const Node *n)
{
    auto num = dynamic_cast<const NumberNode *>(n);
    return num && num->value == 0;
}

std::vector<std::string> SemanticAnalyzer::check(const Node &root)
{
    scopes.clear();
    errors.clear();
    loop_depth = 0;
    block(dynamic_cast<const Block &>(root), true);
    return errors;
}

void SemanticAnalyzer::error(int line, const std::string &message)
{
    errors.push_back("semantic error, line " + std::to_string(line) + ": " + message);
}

const Symbol *SemanticAnalyzer::lookup(const std::string &name) const
{
    for (auto it = scopes.rbegin(); it != scopes.rend(); ++it)
    {
        auto found = it->find(name);
        if (found != it->end()) return &found->second;
    }
    return nullptr;
}

/* ---------- statements ---------- */

void SemanticAnalyzer::block(const Block &b, bool new_scope)
{
    if (new_scope) scopes.emplace_back();
    for (auto &s : b.statements) statement(*s);
    if (new_scope) scopes.pop_back();
}

void SemanticAnalyzer::statement(const Node &n)
{
    if (auto d = dynamic_cast<const Declaration *>(&n))
        declaration(*d);
    else if (auto a = dynamic_cast<const Assignment *>(&n))
        assignment(*a);
    else if (auto inc = dynamic_cast<const IncDec *>(&n))
    {
        if (lvalue(*inc->target, true) == Type::Bool)
            error(inc->line, "'" + inc->op_tok.value + "' needs an int variable, got bool");
    }
    else if (auto s = dynamic_cast<const IfStatement *>(&n))
    {
        condition(*s->cond, "if");
        block(dynamic_cast<const Block &>(*s->then_block), true);
        if (s->else_branch) statement(*s->else_branch);
    }
    else if (auto w = dynamic_cast<const WhileStatement *>(&n))
    {
        condition(*w->cond, "while");
        loop_depth++;
        block(dynamic_cast<const Block &>(*w->body), true);
        loop_depth--;
    }
    else if (auto dw = dynamic_cast<const DoWhileStatement *>(&n))
    {
        loop_depth++;
        block(dynamic_cast<const Block &>(*dw->body), true);
        loop_depth--;
        condition(*dw->cond, "do-while");
    }
    else if (auto f = dynamic_cast<const ForStatement *>(&n))
    {
        scopes.emplace_back(); // the init variable lives only in the loop
        if (f->init) statement(*f->init);
        if (f->cond) condition(*f->cond, "for");
        if (f->update) statement(*f->update);
        loop_depth++;
        block(dynamic_cast<const Block &>(*f->body), true);
        loop_depth--;
        scopes.pop_back();
    }
    else if (dynamic_cast<const BreakStatement *>(&n) || dynamic_cast<const ContinueStatement *>(&n))
    {
        if (loop_depth == 0)
            error(n.line, "'" + std::string(dynamic_cast<const BreakStatement *>(&n) ? "break" : "continue") +
                              "' can only be used inside a loop");
    }
    else if (auto p = dynamic_cast<const PrintStatement *>(&n))
    {
        for (auto &arg : p->args)
            if (!dynamic_cast<const StringNode *>(arg.get())) expression(*arg);
    }
    else if (auto r = dynamic_cast<const ReadStatement *>(&n))
    {
        for (auto &t : r->targets)
            if (lvalue(*t, true) == Type::Bool)
                error(t->line, "read only accepts int variables");
    }
    else if (auto b = dynamic_cast<const Block *>(&n))
        block(*b, true);
}

void SemanticAnalyzer::declaration(const Declaration &d)
{
    Type elem = d.type == "int" ? Type::Int : Type::Bool;

    for (auto &var : d.vars)
    {
        const std::string &name = var->name;
        if (var->is_array() && var->array_size == 0)
            error(var->line, "array '" + name + "' must have a size greater than 0");
        if (d.is_const && !var->init)
            error(var->line, "constant '" + name + "' must be initialised");

        // the initializer is checked before the name exists
        if (auto list = dynamic_cast<const InitList *>(var->init.get()))
        {
            if (!var->is_array())
                error(var->line, "a brace list can only initialise an array, '" + name + "' is not one");
            else if ((int64_t)list->values.size() > var->array_size)
                error(var->line, "too many values for '" + name + "[" + std::to_string(var->array_size) +
                                     "]', got " + std::to_string(list->values.size()));
            for (auto &v : list->values)
            {
                Type t = expression(*v);
                if (known(t) && t != elem)
                    error(v->line, "array '" + name + "' holds " + type_name(elem) + " values, got " + type_name(t));
            }
        }
        else if (var->init)
        {
            Type t = expression(*var->init);
            if (var->is_array())
                error(var->line, "array '" + name + "' must be initialised with a brace list, as in {1, 2, 3}");
            else if (known(t) && t != elem)
                error(var->line, "cannot initialise " + type_name(elem) + " '" + name + "' with " + a_type(t) + " value");
        }

        auto &scope = scopes.back();
        auto existing = scope.find(name);
        if (existing != scope.end())
            error(var->line, "'" + name + "' is already declared in this scope (line " +
                                 std::to_string(existing->second.line) + ")");
        else
            scope[name] = Symbol{elem, d.is_const, var->array_size, var->line};
    }
}

void SemanticAnalyzer::assignment(const Assignment &a)
{
    Type target = lvalue(*a.target, true);
    Type value = expression(*a.expression);
    const std::string &op = a.op_tok.value;

    if (op == "=")
    {
        if (known(target) && known(value) && target != value)
            error(a.line, "cannot assign " + a_type(value) + " value to " + a_type(target) + " variable");
        return;
    }
    if (target == Type::Bool || value == Type::Bool)
        error(a.line, "'" + op + "' needs int operands");
    if ((op == "/=" || op == "%=") && is_zero_literal(a.expression.get()))
        error(a.line, "division by zero");
}

void SemanticAnalyzer::condition(const Node &cond, const std::string &where)
{
    if (expression(cond) == Type::Int)
        error(cond.line, "the " + where + " condition must be bool, got int (compare it, e.g. x != 0)");
}

/* ---------- expressions ---------- */

Type SemanticAnalyzer::lvalue(const Node &n, bool must_be_mutable)
{
    std::string name;
    const ArrayAccessNode *access = dynamic_cast<const ArrayAccessNode *>(&n);
    if (access)
        name = access->name;
    else
        name = dynamic_cast<const IdentifierNode &>(n).getValue();

    const Symbol *sym = lookup(name);
    if (!sym)
    {
        error(n.line, "'" + name + "' is not declared");
        if (access) expression(*access->index);
        return Type::Error;
    }

    if (access)
    {
        Type index = expression(*access->index);
        if (sym->array_size < 0)
        {
            error(n.line, "'" + name + "' is not an array and cannot be indexed");
            return Type::Error;
        }
        if (index == Type::Bool)
            error(n.line, "array index must be an int, got bool");
        if (auto num = dynamic_cast<const NumberNode *>(access->index.get()))
            if (num->value >= sym->array_size)
                error(n.line, "index " + std::to_string(num->value) + " is out of bounds for '" + name + "[" +
                                  std::to_string(sym->array_size) + "]'");
    }
    else if (sym->array_size >= 0)
    {
        error(n.line, "array '" + name + "' must be indexed, as in " + name + "[i]");
        return Type::Error;
    }

    if (must_be_mutable && sym->is_const)
        error(n.line, "cannot modify constant '" + name + "'");
    return sym->type;
}

Type SemanticAnalyzer::expression(const Node &n)
{
    if (dynamic_cast<const NumberNode *>(&n)) return Type::Int;
    if (dynamic_cast<const BoolNode *>(&n)) return Type::Bool;
    if (dynamic_cast<const IdentifierNode *>(&n) || dynamic_cast<const ArrayAccessNode *>(&n))
        return lvalue(n, false);

    if (auto u = dynamic_cast<const UnaryOpNode *>(&n))
    {
        Type t = expression(*u->operand);
        Type need = u->op_tok.value == "!" ? Type::Bool : Type::Int;
        if (known(t) && t != need)
            error(n.line, "operator '" + u->op_tok.value + "' needs " + a_type(need) + " operand, got " + type_name(t));
        return need;
    }

    if (auto b = dynamic_cast<const BinOpNode *>(&n))
    {
        Type l = expression(*b->left);
        Type r = expression(*b->right);
        const std::string &op = b->op_tok.value;
        std::string got = type_name(l) + " and " + type_name(r);

        if (op == "==" || op == "!=")
        {
            if (known(l) && known(r) && l != r)
                error(n.line, "cannot compare " + got + " with '" + op + "'");
            return Type::Bool;
        }
        bool logical = op == "&&" || op == "||";
        bool relational = op == "<" || op == "<=" || op == ">" || op == ">=";
        Type need = logical ? Type::Bool : Type::Int;

        if (known(l) && known(r) && (l != need || r != need))
            error(n.line, "operator '" + op + "' needs " + type_name(need) + " operands, got " + got);
        if ((op == "/" || op == "%") && is_zero_literal(b->right.get()))
            error(n.line, "division by zero");
        if (op == "**")
            if (auto neg = dynamic_cast<const UnaryOpNode *>(b->right.get()))
                if (neg->op_tok.value == "-" && dynamic_cast<const NumberNode *>(neg->operand.get()) &&
                    !is_zero_literal(neg->operand.get()))
                    error(n.line, "negative exponent, integer power needs an exponent >= 0");

        return (logical || relational) ? Type::Bool : Type::Int;
    }

    if (auto t = dynamic_cast<const TernaryNode *>(&n))
    {
        condition(*t->cond, "?:");
        Type a = expression(*t->then_expr);
        Type b = expression(*t->else_expr);
        if (known(a) && known(b) && a != b)
            error(n.line, "both branches of ?: must have the same type, got " + type_name(a) + " and " + type_name(b));
        return known(a) ? a : b;
    }

    return Type::Error;
}
