#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include "tokens.hpp"
#include "parser.hpp"
#include "semantic.hpp"

extern void scan_string_to_tokens(const std::string &src, std::vector<Token> &out);

// pre-order dfs: node first, then children left to right
static void print_tree(const Node *node, const std::string &edge, const std::string &prefix, bool is_last, bool is_root)
{
    std::cout << prefix;
    if (!is_root) std::cout << (is_last ? "`-- " : "|-- ");
    if (!edge.empty()) std::cout << edge << ": ";
    std::cout << node->label() << "\n";

    auto kids = node->children();
    std::string child_prefix = is_root ? "" : prefix + (is_last ? "    " : "|   ");
    for (size_t i = 0; i < kids.size(); i++)
        print_tree(kids[i].node, kids[i].edge, child_prefix, i + 1 == kids.size(), false);
}

void print_ast(const std::shared_ptr<Node> &node)
{
    if (node) print_tree(node.get(), "", "", true, true);
}

static std::string dot_escape(const std::string &s)
{
    std::string out;
    for (char c : s)
    {
        if (c == '"' || c == '\\') out += '\\';
        out += c;
    }
    return out;
}

// same dfs, written as a graphviz graph
static int write_dot_node(std::ostream &out, const Node *node, int &next_id)
{
    int id = next_id++;
    out << "  n" << id << " [label=\"" << dot_escape(node->label()) << "\"];\n";
    for (auto &child : node->children())
    {
        int child_id = write_dot_node(out, child.node, next_id);
        out << "  n" << id << " -> n" << child_id;
        if (!child.edge.empty()) out << " [label=\"" << child.edge << "\"]";
        out << ";\n";
    }
    return id;
}

static void write_dot(const std::shared_ptr<Node> &root, const std::string &path)
{
    std::ofstream out(path);
    if (!out) return;
    out << "digraph AST {\n  node [shape=box, fontname=\"Helvetica\"];\n  edge [fontname=\"Helvetica\", fontsize=10];\n";
    int next_id = 0;
    write_dot_node(out, root.get(), next_id);
    out << "}\n";
}

int main(int argc, char **argv)
{
    std::string path = "../read.txt";
    bool show_tokens = false;
    for (int i = 1; i < argc; i++)
    {
        std::string arg = argv[i];
        if (arg == "--tokens") show_tokens = true;
        else path = arg;
    }

    std::ifstream fin(path);
    if (!fin)
    {
        std::cerr << "Cannot open " << path << "\n";
        return 1;
    }
    std::stringstream buffer;
    buffer << fin.rdbuf();
    std::string input = buffer.str();

    try
    {
        std::vector<Token> toks;
        scan_string_to_tokens(input, toks);
        TokenArray arr;
        for (auto &t : toks)
            arr.push(t);

        if (show_tokens)
        {
            for (auto &t : toks)
                std::cout << "line " << t.line << "\t" << describe(t) << "\n";
            std::cout << "\n";
        }

        Parser parser(arr);
        auto root = parser.get_root();

        std::cout << "Abstract Syntax Tree (depth-first, pre-order)\n\n";
        print_ast(root);
        write_dot(root, "ast.dot");
        std::cout << "\nGraph written to ast.dot (render with: dot -Tpng ast.dot -o ast.png)\n";

        SemanticAnalyzer analyzer;
        auto errors = analyzer.check(*root);
        if (!errors.empty())
        {
            std::cout << std::flush;
            for (auto &e : errors) std::cerr << e << "\n";
            std::cerr << errors.size() << " semantic error(s)\n";
            return 1;
        }
        std::cout << "Semantic analysis: OK\n";
    }
    catch (const std::exception &e)
    {
        std::cerr << e.what() << "\n";
        return 1;
    }
    return 0;
}
