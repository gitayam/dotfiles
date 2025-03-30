document.addEventListener('DOMContentLoaded', function() {
    // ===== SEARCH AND FILTER FUNCTIONALITY =====
    
    // Get filter elements
    const searchInput = document.getElementById('search-input');
    const categoryFilter = document.getElementById('category-filter');
    const typeFilter = document.getElementById('type-filter');
    
    // Get all item cards
    const itemCards = document.querySelectorAll('.item-card');
    
    // Add event listeners for filters
    if (searchInput && categoryFilter && typeFilter) {
        searchInput.addEventListener('input', applyFilters);
        categoryFilter.addEventListener('change', applyFilters);
        typeFilter.addEventListener('change', applyFilters);
    }
    
    // Function to apply all filters
    function applyFilters() {
        const searchTerm = searchInput.value.toLowerCase();
        const categoryValue = categoryFilter.value;
        const typeValue = typeFilter.value;
        
        // Loop through all item cards and check if they match the filters
        itemCards.forEach(card => {
            const cardName = card.getAttribute('data-name').toLowerCase();
            const cardCategory = card.getAttribute('data-category');
            const cardType = card.getAttribute('data-type');
            
            // Check if card matches all filters
            const matchesSearch = cardName.includes(searchTerm);
            const matchesCategory = categoryValue === 'all' || cardCategory === categoryValue;
            const matchesType = typeValue === 'all' || cardType === typeValue;
            
            // Show or hide the card based on filter matches
            if (matchesSearch && matchesCategory && matchesType) {
                card.style.display = '';
            } else {
                card.style.display = 'none';
            }
        });
        
        // Check if sections are empty and hide them if needed
        updateSectionVisibility();
    }
    
    // Function to update section visibility based on visible cards
    function updateSectionVisibility() {
        const sections = document.querySelectorAll('section');
        
        sections.forEach(section => {
            const cards = section.querySelectorAll('.item-card');
            const visibleCards = Array.from(cards).filter(card => card.style.display !== 'none');
            
            if (visibleCards.length === 0) {
                section.style.display = 'none';
            } else {
                section.style.display = '';
            }
        });
    }

    // ===== FORM VALIDATION AND ENHANCEMENT =====
    
    // Get forms if they exist
    const functionForm = document.querySelector('form[action*="function"]');
    const aliasForm = document.querySelector('form[action*="alias"]');
    
    // Add validation to function form
    if (functionForm) {
        functionForm.addEventListener('submit', function(event) {
            const nameInput = document.getElementById('name');
            const bodyInput = document.getElementById('body');
            
            // Validate function name (no spaces, special chars limited)
            if (!/^[a-zA-Z0-9_-]+$/.test(nameInput.value)) {
                event.preventDefault();
                alert('Function name can only contain letters, numbers, underscores, and hyphens.');
                nameInput.focus();
                return false;
            }
            
            // Ensure body is not empty
            if (!bodyInput.value.trim()) {
                event.preventDefault();
                alert('Function body cannot be empty.');
                bodyInput.focus();
                return false;
            }
            
            return true;
        });
    }
    
    // Add validation to alias form
    if (aliasForm) {
        aliasForm.addEventListener('submit', function(event) {
            const nameInput = document.getElementById('name');
            const valueInput = document.getElementById('value');
            
            // Validate alias name (no spaces, special chars limited)
            if (!/^[a-zA-Z0-9_-]+$/.test(nameInput.value)) {
                event.preventDefault();
                alert('Alias name can only contain letters, numbers, underscores, and hyphens.');
                nameInput.focus();
                return false;
            }
            
            // Ensure value is not empty
            if (!valueInput.value.trim()) {
                event.preventDefault();
                alert('Alias value cannot be empty.');
                valueInput.focus();
                return false;
            }
            
            return true;
        });
    }
    
    // Add syntax highlighting to code areas (placeholder for future enhancement)
    const codeBlocks = document.querySelectorAll('pre');
    codeBlocks.forEach(block => {
        // Simple syntax highlighting could be added here in the future
        // For now, just add a class for styling
        block.classList.add('code-block');
    });

    // ===== RESPONSIVE UI ENHANCEMENTS =====
    
    // Add responsive menu toggle for mobile
    const header = document.querySelector('header');
    
    if (header) {
        const menuButton = document.createElement('button');
        menuButton.classList.add('menu-toggle');
        menuButton.innerHTML = '☰';
        menuButton.style.display = 'none'; // Hide by default, show in media query
        
        // Add to DOM
        header.appendChild(menuButton);
        
        // Add media query for mobile
        const mediaQuery = window.matchMedia('(max-width: 768px)');
        
        function handleMobileView(e) {
            if (e.matches) {
                // Mobile view
                menuButton.style.display = 'block';
                document.querySelector('nav').classList.add('mobile-nav');
            } else {
                // Desktop view
                menuButton.style.display = 'none';
                document.querySelector('nav').classList.remove('mobile-nav');
                document.querySelector('nav').style.display = '';
            }
        }
        
        // Initial check
        handleMobileView(mediaQuery);
        
        // Add listener for changes
        mediaQuery.addEventListener('change', handleMobileView);
        
        // Toggle menu on click
        menuButton.addEventListener('click', function() {
            const nav = document.querySelector('nav');
            if (nav.style.display === 'none' || nav.style.display === '') {
                nav.style.display = 'block';
            } else {
                nav.style.display = 'none';
            }
        });
    }
    
    // Add confirmation for delete actions
    const deleteForms = document.querySelectorAll('form[action*="delete"]');
    deleteForms.forEach(form => {
        form.addEventListener('submit', function(event) {
            const confirmed = confirm('Are you sure you want to delete this item? This action cannot be undone.');
            if (!confirmed) {
                event.preventDefault();
                return false;
            }
            return true;
        });
    });
    
    // ===== COMMAND EXECUTION FUNCTIONALITY =====
    
    // Function execution
    const executeFunctionButton = document.getElementById('execute-function');
    if (executeFunctionButton) {
        executeFunctionButton.addEventListener('click', function() {
            const functionName = this.getAttribute('data-function');
            const args = document.getElementById('function-args').value;
            executeFunction(functionName, args);
        });
    }
    
    // Alias execution
    const executeAliasButton = document.getElementById('execute-alias');
    if (executeAliasButton) {
        executeAliasButton.addEventListener('click', function() {
            const aliasName = this.getAttribute('data-alias');
            const args = document.getElementById('alias-args').value;
            executeAlias(aliasName, args);
        });
    }
});

// ===== COMMAND EXECUTION FUNCTIONALITY =====

// Function to execute a shell function
function executeFunction(functionName, args) {
    const executeButton = document.getElementById('execute-function');
    const resultsPanel = document.querySelector('.execution-results');
    const statusElement = document.querySelector('.result-status');
    const stdoutElement = document.querySelector('.stdout-content');
    const stderrElement = document.querySelector('.stderr-content');
    
    // Show loading state
    executeButton.disabled = true;
    executeButton.textContent = 'Executing...';
    resultsPanel.style.display = 'block';
    statusElement.innerHTML = '<span class="status-running">Running...</span>';
    stdoutElement.textContent = '';
    stderrElement.textContent = '';
    
    // Send execution request to the server
    fetch(`/api/execute/function/${functionName}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({ args: args }),
    })
    .then(response => response.json())
    .then(data => {
        // Display the results
        if (data.success) {
            statusElement.innerHTML = '<span class="status-success">Success (exit code: 0)</span>';
        } else {
            statusElement.innerHTML = `<span class="status-error">Error (exit code: ${data.returncode})</span>`;
        }
        
        stdoutElement.textContent = data.stdout || 'No output';
        stderrElement.textContent = data.stderr || 'No errors';
        
        // Reset button state
        executeButton.disabled = false;
        executeButton.textContent = 'Run Function';
    })
    .catch(error => {
        // Handle errors
        statusElement.innerHTML = '<span class="status-error">Execution failed</span>';
        stderrElement.textContent = `Error: ${error.message}`;
        
        // Reset button state
        executeButton.disabled = false;
        executeButton.textContent = 'Run Function';
    });
}

// Function to execute a shell alias
function executeAlias(aliasName, args) {
    const executeButton = document.getElementById('execute-alias');
    const resultsPanel = document.querySelector('.execution-results');
    const statusElement = document.querySelector('.result-status');
    const stdoutElement = document.querySelector('.stdout-content');
    const stderrElement = document.querySelector('.stderr-content');
    
    // Show loading state
    executeButton.disabled = true;
    executeButton.textContent = 'Executing...';
    resultsPanel.style.display = 'block';
    statusElement.innerHTML = '<span class="status-running">Running...</span>';
    stdoutElement.textContent = '';
    stderrElement.textContent = '';
    
    // Send execution request to the server
    fetch(`/api/execute/alias/${aliasName}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({ args: args }),
    })
    .then(response => response.json())
    .then(data => {
        // Display the results
        if (data.success) {
            statusElement.innerHTML = '<span class="status-success">Success (exit code: 0)</span>';
        } else {
            statusElement.innerHTML = `<span class="status-error">Error (exit code: ${data.returncode})</span>`;
        }
        
        stdoutElement.textContent = data.stdout || 'No output';
        stderrElement.textContent = data.stderr || 'No errors';
        
        // Reset button state
        executeButton.disabled = false;
        executeButton.textContent = 'Run Alias';
    })
    .catch(error => {
        // Handle errors
        statusElement.innerHTML = '<span class="status-error">Execution failed</span>';
        stderrElement.textContent = `Error: ${error.message}`;
        
        // Reset button state
        executeButton.disabled = false;
        executeButton.textContent = 'Run Alias';
    });
}