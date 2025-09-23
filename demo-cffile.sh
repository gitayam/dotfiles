#!/bin/zsh

# Demo script showing cffile functionality

echo "🎬 Demonstrating cffile functionality..."
echo ""

# Source the network functions
source .zsh_network

echo "✅ Functions loaded successfully"
echo ""

# Show help
echo "📖 Showing cffile help:"
cffile_function --help

echo ""
echo "🎯 cffile is ready to use!"
echo ""
echo "Usage examples:"
echo "  cffile_function document.pdf                    # Share single file"
echo "  cffile_function -p secret123 document.pdf      # Share with password"
echo "  cffile_function -m -a admin123 -u \"user1:pass1;user2:pass2\" files/"
echo ""
echo "Note: Use 'cffile_function' until your shell properly loads the alias"
echo "      or add 'source .zsh_network' to your shell startup"