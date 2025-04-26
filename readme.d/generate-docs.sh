#!/bin/sh
set -e

echo "Starting documentation generation..."

# Create public directory for output
mkdir -p public

# Display project information
echo "## IYKonect AWS Infrastructure" > public/index.md
echo "Generated on $(date)" >> public/index.md
echo "" >> public/index.md

# Copy README to documentation
echo "### Project README" >> public/index.md
echo "" >> public/index.md
cat ../README.md >> public/index.md
echo "" >> public/index.md

# Generate infrastructure visualization with Rover
echo "### Infrastructure Visualization" >> public/index.md
echo "" >> public/index.md
echo "```" >> public/index.md
echo "Generating infrastructure visualization with Rover..." >> public/index.md

cd ../terraform
rover --workingDir=. --output=../public/diagram.svg || echo "Failed to generate diagram with Rover"
cd ..

echo "```" >> public/index.md
echo "" >> public/index.md
echo "![Infrastructure Diagram](./diagram.svg)" >> public/index.md
echo "" >> public/index.md

# Create infrastructure documentation
echo "### Infrastructure Resources" >> public/index.md
echo "" >> public/index.md

# Generate documentation for modules
for MODULE_DIR in terraform/modules/*; do
  if [ -d "$MODULE_DIR" ]; then
    MODULE_NAME=$(basename "$MODULE_DIR")
    echo "#### Module: $MODULE_NAME" >> public/index.md
    echo "" >> public/index.md
    echo "```hcl" >> public/index.md
    
    for TF_FILE in $MODULE_DIR/*.tf; do
      if [ -f "$TF_FILE" ]; then
        echo "# File: $(basename "$TF_FILE")" >> public/index.md
        cat "$TF_FILE" >> public/index.md
        echo "" >> public/index.md
      fi
    done
    
    echo "```" >> public/index.md
    echo "" >> public/index.md
  fi
done

# Generate HTML file
cat > public/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IYKonect AWS Infrastructure Documentation</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            color: #333;
        }
        .header {
            background-color: #f5f5f5;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        img {
            max-width: 100%;
            height: auto;
        }
        pre {
            background-color: #f5f5f5;
            padding: 15px;
            border-radius: 5px;
            overflow: auto;
        }
        code {
            font-family: 'Courier New', Courier, monospace;
        }
        h2, h3, h4 {
            color: #2c3e50;
        }
        a {
            color: #3498db;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>IYKonect AWS Infrastructure Documentation</h1>
        <p>Generated on $(date)</p>
    </div>
    
    <div id="content">Loading...</div>

    <script>
        fetch('index.md')
            .then(response => response.text())
            .then(text => {
                document.getElementById('content').innerHTML = marked.parse(text);
            });
    </script>
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
</body>
</html>
EOF

echo "Documentation generation complete! Output is in the public directory"