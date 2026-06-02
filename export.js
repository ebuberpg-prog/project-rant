/**
 * Export functionality for Rant app
 * Download specs as .md files and copy to clipboard
 */
const ExportModule = {
  /**
   * Copy text to clipboard
   */
  async copyToClipboard(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (err) {
      // Fallback for older browsers
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      try {
        document.execCommand('copy');
        document.body.removeChild(textarea);
        return true;
      } catch {
        document.body.removeChild(textarea);
        return false;
      }
    }
  },

  /**
   * Download text as a .md file
   */
  downloadAsMarkdown(text, filename = 'spec.md') {
    const blob = new Blob([text], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    return true;
  },

  /**
   * Generate AGENTS.md companion file from a PRD
   */
  generateAgentsMd(prdText) {
    // Simple extraction — in a real app this would be more sophisticated
    // For now, create a basic AGENTS.md template
    const lines = prdText.split('\n');
    let projectName = 'Project';
    let purpose = '';
    let stack = [];

    // Extract project name from first heading
    const titleMatch = prdText.match(/^# PRD:\s*(.+)/m);
    if (titleMatch) {
      projectName = titleMatch[1].trim();
    }

    // Extract purpose from Overview
    const overviewMatch = prdText.match(/## 1\. Overview\s*\n(.+)/);
    if (overviewMatch) {
      purpose = overviewMatch[1].trim();
    }

    // Extract stack
    const stackSection = prdText.match(/### 5\.1 Stack\s*\n([\s\S]*?)(?=###|$)/);
    if (stackSection) {
      const stackLines = stackSection[1].match(/^-\s+\*\*.+?:\*\*\s*(.+)/gm);
      if (stackLines) {
        stack = stackLines.map(l => l.replace(/^-\s+\*\*.*?\*\*\s*/, '').trim());
      }
    }

    return `# AGENTS.md

## Project
- **Name:** ${projectName}
- **Type:** Web Application
- **Purpose:** ${purpose || 'Convert voice rants into structured coding specs'}

## Tech Stack
${stack.map(s => `- ${s}`).join('\n') || '- To be determined from PRD'}

## Commands
| Command | Purpose |
|---------|---------|
| <!-- Add your build/test commands here --> | |

## Code Style
- Use explicit, readable variable names
- Write self-documenting code with comments for complex logic
- Follow the tech stack's official style guide

## Architecture
<!-- Extract from PRD Section 6 -->

## Boundaries
**NEVER:**
- Commit secrets or API keys
- Use hardcoded values that should be configurable
- Skip error handling on external API calls

**ASK:**
- Before adding new dependencies
- Before changing the database schema
- Before modifying CI/CD configuration

**ALWAYS:**
- Write tests for new features
- Validate user inputs
- Handle errors gracefully with user-friendly messages
`;
  },

  /**
   * Generate .cursorrules companion file
   */
  generateCursorRules(prdText) {
    const titleMatch = prdText.match(/^# PRD:\s*(.+)/m);
    const projectName = titleMatch ? titleMatch[1].trim() : 'Project';

    return `# .cursorrules

# Project: ${projectName}

## Context
You are an expert software engineer working on ${projectName}.
Base your work on the PRD and AGENTS.md in this repository.

## Tech Stack
<!-- Fill from PRD Section 5.1 -->

## Code Style
- Prefer functional programming patterns where appropriate
- Use TypeScript strict mode
- Colocate related files (component + test + styles)
- Use named exports over default exports

## Testing
- Write unit tests for utility functions
- Write integration tests for API routes
- Write E2E tests for critical user flows

## Constraints
- Never commit .env files
- Never expose API keys in client-side code
- Always validate external API responses
- Always handle loading and error states in UI
`;
  }
};
