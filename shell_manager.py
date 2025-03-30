#!/usr/bin/env python3
import os
import re
import sys
import json
import platform
import subprocess
from pathlib import Path
from flask import Flask, render_template, request, jsonify, redirect, url_for

app = Flask(__name__, static_folder='static', template_folder='templates')
app.config['SECRET_KEY'] = 'shell-function-manager-secret-key'
app.config['JSON_SORT_KEYS'] = False

# Determine OS and set appropriate paths
SYSTEM = platform.system()
HOME_DIR = str(Path.home())

# Configuration for different operating systems
CONFIG = {
    'Darwin': {  # macOS
        'shell': 'zsh',
        'config_dir': os.path.join(os.path.dirname(os.path.abspath(__file__)), 'macos'),
        'files': {
            'aliases': ['.zsh_aliases'],
            'functions': ['.zsh_functions', '.zsh_git', '.zsh_apps', '.zsh_network', 
                         '.zsh_transfer', '.zsh_security', '.zsh_utils', '.zsh_docker'],
            'main': ['.zshrc']
        }
    },
    'Linux': {
        'shell': 'bash',
        'config_dir': os.path.join(os.path.dirname(os.path.abspath(__file__)), 'linux'),
        'files': {
            'aliases': ['.bash_aliases'],
            'functions': ['.bash_aliases', '.bash_functions.sh'],
            'main': ['.bashrc']
        }
    }
}

# Use the current OS configuration
current_config = CONFIG.get(SYSTEM, CONFIG['Linux'])

def parse_function(content, start_idx):
    """Parse a shell function from the content starting at start_idx."""
    # Find the function name
    function_line = content[start_idx].strip()
    if '(' in function_line:
        function_name = function_line.split('(')[0].strip()
    else:
        function_name = function_line.split()[1].strip()
    
    # Find the function body
    body_start = start_idx + 1
    body_end = body_start
    brace_count = 1
    
    while body_end < len(content) and brace_count > 0:
        line = content[body_end]
        if '{' in line:
            brace_count += line.count('{')
        if '}' in line:
            brace_count -= line.count('}')
        body_end += 1
    
    # Extract the function body
    function_body = '\n'.join(content[body_start:body_end])
    
    # Extract any comments above the function as documentation
    doc_lines = []
    doc_idx = start_idx - 1
    while doc_idx >= 0 and (content[doc_idx].strip().startswith('#') or content[doc_idx].strip() == ''):
        if content[doc_idx].strip().startswith('#'):
            doc_lines.insert(0, content[doc_idx])
        doc_idx -= 1
    
    documentation = '\n'.join(doc_lines)
    
    return {
        'name': function_name,
        'body': function_body,
        'documentation': documentation,
        'line_start': start_idx,
        'line_end': body_end - 1
    }

def parse_alias(line):
    """Parse an alias definition from a line."""
    # Remove 'alias' prefix and any comments
    alias_def = line.strip()[6:].split('#')[0].strip()
    
    # Split at the first '=' to get name and value
    if '=' in alias_def:
        name, value = alias_def.split('=', 1)
        name = name.strip()
        value = value.strip().strip('"\'')
        return {'name': name, 'value': value}
    return None

def load_shell_files():
    """Load and parse all shell configuration files."""
    shell_data = {
        'functions': [],
        'aliases': []
    }
    
    # Process function files
    for file_type, file_list in current_config['files'].items():
        for file_name in file_list:
            file_path = os.path.join(current_config['config_dir'], file_name)
            if not os.path.exists(file_path):
                continue
                
            with open(file_path, 'r') as f:
                content = f.read().splitlines()
            
            category = file_name.replace('.', '').replace('zsh_', '').replace('bash_', '')
            
            # Parse functions and aliases
            i = 0
            while i < len(content):
                line = content[i].strip()
                
                # Parse functions
                if (line.endswith('() {') or 
                    line.startswith('function ') and '{' in line):
                    func = parse_function(content, i)
                    func['file'] = file_name
                    func['category'] = category
                    shell_data['functions'].append(func)
                    i = func['line_end'] + 1
                # Parse aliases
                elif line.startswith('alias '):
                    alias = parse_alias(line)
                    if alias:
                        alias['file'] = file_name
                        alias['category'] = category
                        alias['line'] = i
                        shell_data['aliases'].append(alias)
                i += 1
    
    return shell_data

def save_function(function_data):
    """Save a function to its file."""
    file_path = os.path.join(current_config['config_dir'], function_data['file'])
    
    with open(file_path, 'r') as f:
        content = f.read().splitlines()
    
    # Prepare the new function content
    new_function_lines = []
    
    # Add documentation
    if function_data['documentation']:
        new_function_lines.extend(function_data['documentation'].splitlines())
    
    # Add function declaration
    if '(' in function_data['name']:
        new_function_lines.append(f"{function_data['name']} {{")
    else:
        new_function_lines.append(f"{function_data['name']}() {{")
    
    # Add function body
    new_function_lines.extend(function_data['body'].splitlines())
    
    # If this is an existing function, replace it
    if 'line_start' in function_data and 'line_end' in function_data:
        content[function_data['line_start']:function_data['line_end']+1] = new_function_lines
    else:
        # Otherwise, append to the end of the file
        content.append('')  # Add a blank line
        content.extend(new_function_lines)
    
    # Write back to the file
    with open(file_path, 'w') as f:
        f.write('\n'.join(content))
    
    return True

def save_alias(alias_data):
    """Save an alias to its file."""
    file_path = os.path.join(current_config['config_dir'], alias_data['file'])
    
    with open(file_path, 'r') as f:
        content = f.read().splitlines()
    
    # Prepare the new alias line
    new_alias_line = f"alias {alias_data['name']}='{alias_data['value']}'"
    
    # If this is an existing alias, replace it
    if 'line' in alias_data:
        content[alias_data['line']] = new_alias_line
    else:
        # Otherwise, append to the end of the file
        content.append(new_alias_line)
    
    # Write back to the file
    with open(file_path, 'w') as f:
        f.write('\n'.join(content))
    
    return True

def delete_function(function_data):
    """Delete a function from its file."""
    file_path = os.path.join(current_config['config_dir'], function_data['file'])
    
    with open(file_path, 'r') as f:
        content = f.read().splitlines()
    
    # Remove the function
    if 'line_start' in function_data and 'line_end' in function_data:
        del content[function_data['line_start']:function_data['line_end']+1]
    
    # Write back to the file
    with open(file_path, 'w') as f:
        f.write('\n'.join(content))
    
    return True

def delete_alias(alias_data):
    """Delete an alias from its file."""
    file_path = os.path.join(current_config['config_dir'], alias_data['file'])
    
    with open(file_path, 'r') as f:
        content = f.read().splitlines()
    
    # Remove the alias
    if 'line' in alias_data:
        del content[alias_data['line']]
    
    # Write back to the file
    with open(file_path, 'w') as f:
        f.write('\n'.join(content))
    
    return True

def execute_shell_command(command, shell_type=None):
    """Execute a shell command and return the output."""
    if not shell_type:
        shell_type = current_config['shell']
    
    try:
        # Execute the command in the appropriate shell
        process = subprocess.Popen(
            [shell_type, '-c', command],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        stdout, stderr = process.communicate(timeout=30)  # 30 second timeout
        
        return {
            'success': process.returncode == 0,
            'stdout': stdout,
            'stderr': stderr,
            'returncode': process.returncode
        }
    except subprocess.TimeoutExpired:
        return {
            'success': False,
            'stdout': '',
            'stderr': 'Command execution timed out after 30 seconds',
            'returncode': -1
        }
    except Exception as e:
        return {
            'success': False,
            'stdout': '',
            'stderr': f'Error executing command: {str(e)}',
            'returncode': -1
        }

def get_categories():
    """Get all categories from the configuration files."""
    categories = set()
    
    for file_type, file_list in current_config['files'].items():
        for file_name in file_list:
            category = file_name.replace('.', '').replace('zsh_', '').replace('bash_', '')
            categories.add(category)
    
    return sorted(list(categories))

@app.route('/')
def index():
    """Render the main page."""
    shell_data = load_shell_files()
    categories = get_categories()
    return render_template('index.html', 
                          functions=shell_data['functions'], 
                          aliases=shell_data['aliases'],
                          categories=categories,
                          system=SYSTEM,
                          shell=current_config['shell'])

@app.route('/function/<name>')
def view_function(name):
    """View a specific function."""
    shell_data = load_shell_files()
    function = next((f for f in shell_data['functions'] if f['name'] == name), None)
    
    if not function:
        return redirect(url_for('index'))
    
    return render_template('function.html', function=function)

@app.route('/alias/<name>')
def view_alias(name):
    """View a specific alias."""
    shell_data = load_shell_files()
    alias = next((a for a in shell_data['aliases'] if a['name'] == name), None)
    
    if not alias:
        return redirect(url_for('index'))
    
    return render_template('alias.html', alias=alias)

@app.route('/function/edit/<name>', methods=['GET', 'POST'])
def edit_function(name):
    """Edit a specific function."""
    shell_data = load_shell_files()
    function = next((f for f in shell_data['functions'] if f['name'] == name), None)
    
    if not function:
        return redirect(url_for('index'))
    
    if request.method == 'POST':
        function['name'] = request.form['name']
        function['body'] = request.form['body']
        function['documentation'] = request.form['documentation']
        
        save_function(function)
        return redirect(url_for('view_function', name=function['name']))
    
    return render_template('edit_function.html', function=function)

@app.route('/alias/edit/<name>', methods=['GET', 'POST'])
def edit_alias(name):
    """Edit a specific alias."""
    shell_data = load_shell_files()
    alias = next((a for a in shell_data['aliases'] if a['name'] == name), None)
    
    if not alias:
        return redirect(url_for('index'))
    
    if request.method == 'POST':
        alias['name'] = request.form['name']
        alias['value'] = request.form['value']
        
        save_alias(alias)
        return redirect(url_for('view_alias', name=alias['name']))
    
    return render_template('edit_alias.html', alias=alias)

@app.route('/function/new', methods=['GET', 'POST'])
def new_function():
    """Create a new function."""
    if request.method == 'POST':
        function = {
            'name': request.form['name'],
            'body': request.form['body'],
            'documentation': request.form['documentation'],
            'file': request.form['file'],
            'category': request.form['file'].replace('.', '').replace('zsh_', '').replace('bash_', '')
        }
        
        save_function(function)
        return redirect(url_for('view_function', name=function['name']))
    
    # Get available files for the function
    function_files = []
    for file_name in current_config['files']['functions']:
        file_path = os.path.join(current_config['config_dir'], file_name)
        if os.path.exists(file_path):
            function_files.append(file_name)
    
    return render_template('new_function.html', files=function_files)

@app.route('/alias/new', methods=['GET', 'POST'])
def new_alias():
    """Create a new alias."""
    if request.method == 'POST':
        alias = {
            'name': request.form['name'],
            'value': request.form['value'],
            'file': request.form['file'],
            'category': request.form['file'].replace('.', '').replace('zsh_', '').replace('bash_', '')
        }
        
        save_alias(alias)
        return redirect(url_for('view_alias', name=alias['name']))
    
    # Get available files for the alias
    alias_files = []
    for file_name in current_config['files']['aliases']:
        file_path = os.path.join(current_config['config_dir'], file_name)
        if os.path.exists(file_path):
            alias_files.append(file_name)
    
    return render_template('new_alias.html', files=alias_files)

@app.route('/function/delete/<name>', methods=['POST'])
def delete_function_route(name):
    """Delete a specific function."""
    shell_data = load_shell_files()
    function = next((f for f in shell_data['functions'] if f['name'] == name), None)
    
    if function:
        delete_function(function)
    
    return redirect(url_for('index'))

@app.route('/alias/delete/<name>', methods=['POST'])
def delete_alias_route(name):
    """Delete a specific alias."""
    shell_data = load_shell_files()
    alias = next((a for a in shell_data['aliases'] if a['name'] == name), None)
    
    if alias:
        delete_alias(alias)
    
    return redirect(url_for('index'))

@app.route('/api/functions')
def api_functions():
    """API endpoint to get all functions."""
    shell_data = load_shell_files()
    return jsonify(shell_data['functions'])

@app.route('/api/aliases')
def api_aliases():
    """API endpoint to get all aliases."""
    shell_data = load_shell_files()
    return jsonify(shell_data['aliases'])

@app.route('/api/categories')
def api_categories():
    """API endpoint to get all categories."""
    categories = get_categories()
    return jsonify(categories)

@app.route('/api/execute/function/<name>', methods=['POST'])
def execute_function(name):
    """Execute a shell function and return the output."""
    shell_data = load_shell_files()
    function = next((f for f in shell_data['functions'] if f['name'] == name), None)
    
    if not function:
        return jsonify({
            'success': False,
            'stdout': '',
            'stderr': f'Function {name} not found',
            'returncode': -1
        }), 404
    
    # Get any arguments passed in the request
    args = request.json.get('args', '')
    
    # Execute the function with arguments, making sure to source the file first
    source_cmd = f"source {os.path.join(current_config['config_dir'], function['file'])} && {function['name']} {args}"
    result = execute_shell_command(source_cmd)
    
    return jsonify(result)

@app.route('/api/execute/alias/<name>', methods=['POST'])
def execute_alias(name):
    """Execute a shell alias and return the output."""
    shell_data = load_shell_files()
    alias = next((a for a in shell_data['aliases'] if a['name'] == name), None)
    
    if not alias:
        return jsonify({
            'success': False,
            'stdout': '',
            'stderr': f'Alias {name} not found',
            'returncode': -1
        }), 404
    
    # Get any arguments passed in the request
    args = request.json.get('args', '')
    
    # For aliases, we need to source the alias file first, then execute
    source_cmd = f"source {os.path.join(current_config['config_dir'], alias['file'])} && {alias['name']} {args}"
    result = execute_shell_command(source_cmd)
    
    return jsonify(result)

if __name__ == '__main__':
    # Check if Flask is installed
    try:
        import flask
    except ImportError:
        print("Flask is not installed. Installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "flask"])
        print("Flask installed successfully.")
    
    print(f"Shell Function Manager starting for {SYSTEM} ({current_config['shell']})")
    print(f"Configuration directory: {current_config['config_dir']}")
    print("Available at http://0.0.0.0:5000")
    app.run(debug=True, host='0.0.0.0')