# Compiler-Design

A small compiler front end written in C++17 for a C-like teaching language, built for the Formal Languages & Architecture course at ISEP. It reads a source file, then:

1. **Lexical analysis**: a Flex scanner turns the text into tokens.
2. **Syntax analysis**: a hand-written recursive-descent parser builds an Abstract Syntax Tree (AST).
3. **AST output**: prints the tree to the terminal and writes it as a Graphviz graph (`ast.dot`).
4. **Semantic analysis**: checks scopes, types, constants, array bounds and loop rules.

Each phase reports clear errors with line numbers. The project is named `CompilerForNASMCpp` in CMake; its long-term goal is to generate NASM assembly. The intermediate representation (IR) and code generation stages are still in progress.

---

## Project structure

```
Compiler-Design/
├── CMakeLists.txt        # Build configuration (C++17 + Flex)
├── read.txt              # Default input program (course example plus language extensions)
├── include/
│   ├── tokens.hpp        # TokenType enum, Token struct, TokenArray, integer literal parsing
│   ├── ast.hpp           # AST node types (expressions, statements, declarations)
│   ├── parser.hpp        # Recursive-descent Parser class
│   └── semantic.hpp      # SemanticAnalyzer and symbol table
├── src/
│   ├── scanner.l         # Flex lexer specification (generates scanner.cpp at build time)
│   ├── parser.cpp        # Parser, one method per grammar rule
│   ├── semantic.cpp      # Semantic checks
│   ├── main.cpp          # Entry point: runs the pipeline, prints the AST, writes ast.dot
│   ├── parser.yy         # Bison grammar: alternative parser building the same AST (--bison)
│   └── ir.cpp            # Intermediate representation (work in progress, see include/ir.hpp)
└── examples/
    ├── gcd.txt              # Valid program
    ├── lexical_error.txt    # Shows lexical errors
    ├── syntax_error.txt     # Shows a syntax error
    └── semantic_error.txt   # Shows semantic errors
```

---

## Requirements

| Tool | Version | Install on macOS | Install on Debian/Ubuntu |
|------|---------|------------------|--------------------------|
| C++ compiler | C++17 (clang or g++) | `xcode-select --install` | `sudo apt install build-essential` |
| CMake | 3.16 or later | `brew install cmake` | `sudo apt install cmake` |
| Flex | any recent version | preinstalled, or `brew install flex` | `sudo apt install flex` |
| Bison *(optional)* | 3.6 or later | `brew install bison` | `sudo apt install bison` |
| Graphviz *(optional)* | any | `brew install graphviz` | `sudo apt install graphviz` |

Bison is only needed for the `--bison` parser. macOS ships Bison 2.3, which is too old; CMake automatically finds Homebrew's Bison instead. Without Bison 3.6 or later, the project still builds, just without `--bison`.
Graphviz is only needed to render `ast.dot` as an image.

---

## Build

From the project root:

```bash
cmake -S . -B build
cmake --build build
```

This produces the executable `build/compiler`.

> **Note:** `CMakeLists.txt` compiles every `.cpp` file in `src/`. `src/ir.cpp` and `include/ir.hpp` still use the course starter's AST (`Statement`, `Condition`, `Assignment::identifier`, ...), which is not the AST in `include/ast.hpp`, so the build fails until the IR is ported. Until then, move `ir.cpp` out of `src/` to build.

---

## Run

```bash
cd build
./compiler [--tokens] [--bison] [path/to/source.txt]
```

| Argument | Meaning |
|----------|---------|
| `path/to/source.txt` | Program to compile. Defaults to `../read.txt`, so run it from `build/` if you leave this out. |
| `--tokens` | Also prints the token stream (one token per line, with its line number) before the AST. |
| `--bison` | Parses with the Bison grammar (`src/parser.yy`) instead of the hand-written recursive-descent parser. Both build the same AST; only the wording of syntax errors differs. |

### Examples

```bash
cd build

./compiler                                   # compile ../read.txt
./compiler ../examples/gcd.txt               # valid program
./compiler --tokens ../examples/gcd.txt      # show the tokens too
./compiler --bison ../examples/gcd.txt       # same program, Bison parser

./compiler ../examples/lexical_error.txt     # lexical errors
./compiler ../examples/syntax_error.txt      # syntax error
./compiler ../examples/semantic_error.txt    # semantic errors
```

### Render the AST as an image

Each successful parse writes `ast.dot` in the current directory:

```bash
dot -Tpng ast.dot -o ast.png
open ast.png        # macOS; use xdg-open on Linux
```

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | The program is lexically, syntactically and semantically valid |
| `1` | The file could not be opened, or a lexical, syntax or semantic error was found |

---

## Sample output

`./compiler ../examples/gcd.txt`:

```
Abstract Syntax Tree (depth-first, pre-order)

Program
|-- Declaration int
|   |-- VarDecl a
|   |   `-- init: Number 0
|   `-- VarDecl b
|       `-- init: Number 5
|-- While
|   |-- cond: BinOp !=
|   |   |-- left: Identifier b
|   |   `-- right: Number 0
|   `-- body: Block
|       `-- If
|           ...
`-- Print
    |-- String "gcd = "
    `-- Identifier a

Graph written to ast.dot (render with: dot -Tpng ast.dot -o ast.png)
Semantic analysis: OK
```

`./compiler ../examples/semantic_error.txt`:

```
semantic error, line 2: too many values for 'a[3]', got 4
semantic error, line 3: cannot initialise bool 'done' with an int value
semantic error, line 4: cannot modify constant 'MAX'
semantic error, line 5: 'y' is not declared
semantic error, line 5: 'break' can only be used inside a loop
semantic error, line 6: the while condition must be bool, got int (compare it, e.g. x != 0)
semantic error, line 6: index 7 is out of bounds for 'a[3]'
7 semantic error(s)
```

---

## The language

### Types and declarations

```c
int x;                          // integer (64-bit)
bool done = false;              // boolean
const int MAX = 1_000;          // constant, must be initialised
int a[5] = {1, 2, 3}, n, m = 0; // arrays and several variables in one declaration
```

Integer literals can be decimal (`42`), hexadecimal (`0xFF`) or binary (`0b1010`), with optional `_` separators (`1_000`).

### Statements

| Statement | Example |
|-----------|---------|
| Assignment | `x = 1;` `x += 2;` (also `-= *= /= %= &= \|= ^= <<= >>=`) |
| Increment / decrement | `i++;` `--i;` |
| If / else if / else | `if (x > 0) { ... } else if (x == 0) { ... } else { ... }` |
| While | `while (x < 10) { ... }` |
| Do-while | `do { ... } while (!done);` |
| For | `for (int i = 0; i < 5; i++) { ... }` |
| Break / continue | `break;` `continue;` (inside loops only) |
| Print | `print("x = ", x, "\n");` |
| Prints (string) | `prints("hello");` |
| Read | `read(n);` (int variables only) |
| Nested block | `{ int n = 3; print(n); }` (opens a new scope) |

Comments: `// line` and `/* block */`.
String escapes: `\n \t \r \f \b \" \\`.

### Operator precedence (lowest to highest)

| Level | Operators | Associativity |
|-------|-----------|---------------|
| Conditional | `? :` | right |
| Logical OR | `\|\|` | left |
| Logical AND | `&&` | left |
| Equality | `== !=` | left |
| Relational | `< <= > >=` | left |
| Bitwise OR | `\|` | left |
| Bitwise XOR | `^` | left |
| Bitwise AND | `&` | left |
| Shift | `<< >>` | left |
| Additive | `+ -` | left |
| Multiplicative | `* / %` | left |
| Unary | `- ! ~` | right |
| Power | `**` | right |

---

## Error checking

| Phase | Examples of detected errors |
|-------|-----------------------------|
| **Lexical** | unexpected characters, malformed numbers (`2x`), integer overflow, invalid string escapes, unterminated strings or comments. All lexical errors are reported together. |
| **Syntax** | missing `;`, `)` or `}`, unexpected tokens, keywords used as names, `=` used where `==` was intended. Parsing stops at the first syntax error. |
| **Semantic** | undeclared or redeclared variables, type mismatches (int and bool), changing a `const`, uninitialised constants, array size, index and initialiser errors, non-bool conditions, `break` or `continue` outside a loop, division by zero by a constant, negative constant exponents, `?:` branches with different types. All semantic errors are reported together. |

---

## Roadmap

- [x] Lexer (Flex)
- [x] Recursive-descent parser and AST
- [x] AST printing and Graphviz export
- [x] Semantic analysis
- [x] Bison grammar (`src/parser.yy`)
- [ ] Intermediate representation (`src/ir.cpp`)
- [ ] NASM code generation
