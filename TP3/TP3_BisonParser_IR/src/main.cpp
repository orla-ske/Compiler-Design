#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>
#include "tokens.hpp"
#include "ast.hpp"
#include "ir.hpp"


// if flex's buffer type isn't visible, declare it.
    typedef struct yy_buffer_state *YY_BUFFER_STATE;
    YY_BUFFER_STATE yy_scan_string(const char* str);
    void yy_delete_buffer(YY_BUFFER_STATE b);

// provided by bison (parser.yy)
extern int yyparse(void);
extern std::shared_ptr<Node> g_ast_root; // the global ast root

// the scanner stores identifiers with a v prefix; print the name as it appears in the source.
static std::string source_name(const Token &tok)
{
    if (tok.type == TokenType::Var && !tok.value.empty() && tok.value[0] == 'V')
        return tok.value.substr(1);
    return tok.value;
}

// statements builds a left leaning chain: left is everything before, right is the newest statement.
static void flatten(const std::shared_ptr<Node> &node, std::vector<std::shared_ptr<Node>> &out)
{
    auto st = std::dynamic_pointer_cast<Statement>(node);
    if (!st)
    {
        if (node)
            out.push_back(node);
        return;
    }
    flatten(st->left, out);
    out.push_back(st->right);
}

static void print_ast(const std::shared_ptr<Node> &node, int depth, const std::string &role = "")
{
    std::string indent(depth * 2, ' ');
    std::string suffix = role.empty() ? "" : " [" + role + "]";

    if (!node)
    {
        std::cout << indent << "(empty)" << suffix << "\n";
    }
    else if (auto st = std::dynamic_pointer_cast<Statement>(node))
    {
        std::cout << indent << "Statement" << suffix << "\n";
        std::vector<std::shared_ptr<Node>> items;
        flatten(st, items);
        for (const auto &item : items)
            print_ast(item, depth + 1);
    }
    else if (auto num = std::dynamic_pointer_cast<NumberNode>(node))
    {
        std::cout << indent << "NumberNode " << num->getValue() << suffix << "\n";
    }
    else if (auto id = std::dynamic_pointer_cast<IdentifierNode>(node))
    {
        std::cout << indent << "IdentifierNode " << source_name(id->tok) << suffix << "\n";
    }
    else if (auto bin = std::dynamic_pointer_cast<BinOpNode>(node))
    {
        std::cout << indent << "BinOpNode " << bin->op_tok.value << suffix << "\n";
        print_ast(bin->left, depth + 1);
        print_ast(bin->right, depth + 1);
    }
    else if (auto cond = std::dynamic_pointer_cast<Condition>(node))
    {
        std::cout << indent << "Condition " << cond->comparison.value << suffix << "\n";
        print_ast(cond->left_expression, depth + 1);
        print_ast(cond->right_expression, depth + 1);
    }
    else if (auto if_st = std::dynamic_pointer_cast<IfStatement>(node))
    {
        std::cout << indent << "IfStatement" << suffix << "\n";
        print_ast(if_st->if_condition, depth + 1);
        print_ast(if_st->if_body, depth + 1, "if body");
        if (if_st->else_body)
            print_ast(if_st->else_body, depth + 1, "else body");
    }
    else if (auto loop = std::dynamic_pointer_cast<WhileStatement>(node))
    {
        std::cout << indent << "WhileStatement" << suffix << "\n";
        print_ast(loop->condition, depth + 1);
        print_ast(loop->body, depth + 1, "body");
    }
    else if (auto print = std::dynamic_pointer_cast<PrintStatement>(node))
    {
        if (print->type == "string")
        {
            std::cout << indent << "PrintStatement string \"" << print->strValue << "\"" << suffix << "\n";
        }
        else
        {
            std::cout << indent << "PrintStatement int" << suffix << "\n";
            print_ast(print->intExpr, depth + 1);
        }
    }
    else if (auto assign = std::dynamic_pointer_cast<Assignment>(node))
    {
        std::cout << indent << "Assignment " << source_name(assign->identifier) << suffix << "\n";
        print_ast(assign->expression, depth + 1);
    }
    else if (auto decl = std::dynamic_pointer_cast<Declaration>(node))
    {
        std::cout << indent << "Declaration " << decl->declaration_type.value;
        for (size_t i = 0; i < decl->identifiers.size(); ++i)
            std::cout << (i == 0 ? " " : ", ") << source_name(decl->identifiers[i]);
        std::cout << suffix << "\n";
    }
    else
    {
        std::cout << indent << "UnknownNode" << suffix << "\n";
    }
}

int main(int argc, char *argv[])
{
    std::string path = argc > 1 ? argv[1] : "../read.txt";
    std::ifstream fin(path);
    if (!fin) { std::cerr << "Cannot open " << path << "\n"; return 1; }

    std::stringstream buffer;
    buffer << fin.rdbuf();
    std::string input = buffer.str();

    YY_BUFFER_STATE buf = yy_scan_string(input.c_str());
    int parse_result = 1;
    try
    {
        parse_result = yyparse();
    }
    catch (const std::exception &e)
    {
        std::cerr << "Error: " << e.what() << "\n";
    }
    yy_delete_buffer(buf);

    if (parse_result != 0)
    {
        std::cerr << "Parsing failed.\n";
        return 1;
    }

    std::cout << "Parsing successful!\n";
    print_ast(g_ast_root, 0);
    //auto root = g_ast_root;
    //IntermediateCodeGen irgen(root);
    //auto gen = irgen.get();
    return 0;
}
