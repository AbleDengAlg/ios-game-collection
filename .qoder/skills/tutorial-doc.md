# Skill: tutorial-doc

Generate comprehensive tutorial documentation for a code project.

## Trigger

When the user asks to create a tutorial, teaching document, or learning guide for a project or codebase.

## Instructions

You are a patient programming teacher. Generate a `TUTORIAL.md` file that teaches a beginner to understand the project line by line. Follow this exact structure:

### Step 1: Analyze the Project

1. Read ALL source code files in the project directory (recursively find `.swift`, `.py`, `.js`, `.ts`, `.java`, `.c`, `.cpp`, `.kt`, `.go`, `.rs` etc.)
2. Identify the program entry point file
3. Identify the core logic/engine files
4. Identify the UI/interface files
5. Identify resource/data files
6. Map the data flow: user input → processing → output

### Step 2: Generate TUTORIAL.md

Create the document with these sections IN ORDER:

#### Section 1: Project Overview (项目总览)
- File tree diagram with one-line description per file
- Data flow diagram using ASCII art (arrows showing how data moves through the system)

#### Section 2: Program Entry Point (程序入口)
- Show the COMPLETE entry point file code with numbered annotations
- A table mapping each annotation number to its explanation
- Key syntax highlights for the entry point file

#### Section 3: Core Engine (核心引擎)
- For EACH function in the core file:
  - Show the function code with numbered inline comments
  - A table explaining each line annotation
  - Key syntax used in this function
- Group functions logically (initialization, processing, output)
- Highlight the MOST IMPORTANT function and explain why

#### Section 4: UI Layer (用户界面)
- Show the main view code with numbered annotations
- Explain each UI component and its data binding
- For custom sub-components, show complete code with annotations

#### Section 5: Syntax Reference (语法速查)
- A table of ALL key language syntax used in the project
- Columns: Keyword | Purpose | Usage in this project
- Layout/container diagram (VStack, HStack, ZStack or equivalent)

#### Section 6: Beginner Pitfalls (新手注意事项)
- List 5 most important things beginners must remember
- Show ❌ wrong code vs ✅ correct code for each
- Common errors specific to this project type

#### Section 7: Extension Exercise 1 — Feature Modification
- Pick one practical modification (e.g., changing time signature, adding difficulty levels, changing grid size)
- Show EXACT code changes needed with before/after comparison
- Mark which file and which line to change

#### Section 8: Extension Exercise 2 — UI Redesign
- Pick one UI change (e.g., horizontal to vertical layout, color scheme change)
- Show COMPLETE replacement code for the affected component
- Include a before/after ASCII visual comparison

#### Section 9: More Extension Ideas
- A table with 6-8 extension directions and brief implementation hints
- Ideas should range from easy (1-line change) to advanced (new framework)

#### Appendix: Git Push Commands
- Show the exact terminal commands to commit and push the tutorial
- Keep it simple: cd → git status → git add → git commit → git push

### Step 3: Update README

Add a link to the tutorial in the project's README.md file, near the relevant project section.

## Rules

- Write in the user's preferred language (detect from their messages)
- Use tables extensively — they are the most readable format for beginners
- Every code block must have numbered annotations that reference explanation tables
- Use ASCII art diagrams for data flow and layout comparisons
- Show COMPLETE code for extension exercises, not just snippets
- Always include ❌ vs ✅ examples in the pitfalls section
- The tone should be friendly and encouraging, like a patient teacher
- Do NOT skip any function — explain every single one
- For `private` functions, explain WHY they are private
- For `@Published` / reactive properties, explain the data flow to UI
- Keep lines under 80 characters in tables for readability
