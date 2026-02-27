// Application Logic with Manual Tracing
// Same-origin API via Nginx proxy - no CORS issues, works across all environments
const API_URL = '/api';

// Global state
let tasks = [];

// Initialize app
document.addEventListener('DOMContentLoaded', () => {
    console.log('Task Manager App initialized');
    setupDynamicLinks();
    loadTasks();
    setupEventListeners();
});

// Setup dynamic observability links based on current hostname
function setupDynamicLinks() {
    const host = window.location.hostname;

    const links = {
        'link-grafana': `http://${host}:3000`,
        'link-prometheus': `http://${host}:9090`,
        'link-tempo': `http://${host}:3200`,
        'link-collector': `http://${host}:8888/metrics`
    };

    for (const [id, href] of Object.entries(links)) {
        const link = document.getElementById(id);
        if (link) {
            link.href = href;
        }
    }

    console.log('[INFO] Dynamic observability links configured for host:', host);
}

// Setup event listeners
function setupEventListeners() {
    const form = document.getElementById('task-form');
    form.addEventListener('submit', handleFormSubmit);

    // DB smoke test button
    const btnDbSmoke = document.getElementById('btn-db-smoke');
    if (btnDbSmoke) {
        btnDbSmoke.addEventListener('click', async () => {
            const startTime = performance.now();
            console.log('[TRACE] Starting DB smoke test');
            showToast('DB smoke test started (300 ops)...', 'warning');

            try {
                // 300 ops mixed read/write; adjust as needed
                const url = `${API_URL}/smoke/db?ops=300&type=rw`;
                const response = await fetch(url, { method: 'POST' });

                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }

                const data = await response.json();
                const duration = performance.now() - startTime;

                console.log('[DB SMOKE]', data);
                console.log(`[METRIC] DB smoke test completed in ${duration.toFixed(2)}ms`);

                showToast(`DB smoke completed: ${data.performed.read} reads, ${data.performed.write} writes. Give Grafana ~1-2 min to show P95.`, 'success');
            } catch (error) {
                console.error('[ERROR] DB smoke test failed:', error);
                const duration = performance.now() - startTime;
                console.log(`[METRIC] DB smoke test failed after ${duration.toFixed(2)}ms`);
                showToast('DB smoke test failed - see console for details.', 'error');
            }
        });
    }
}

// Load all tasks
async function loadTasks() {
    const startTime = performance.now();

    try {
        console.log('[TRACE] Starting loadTasks operation');

        const response = await fetch(`${API_URL}/tasks`, {
            method: 'GET',
            headers: {
                'Content-Type': 'application/json',
                'X-Operation': 'load-tasks',
            },
        });

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        tasks = data.tasks || [];

        const duration = performance.now() - startTime;
        console.log(`[METRIC] loadTasks completed in ${duration.toFixed(2)}ms`);
        console.log(`[METRIC] Loaded ${tasks.length} tasks`);

        renderTasks();
        updateStats();
        showToast('Tasks loaded successfully', 'success');
    } catch (error) {
        console.error('[ERROR] Failed to load tasks:', error);
        const duration = performance.now() - startTime;
        console.log(`[METRIC] loadTasks failed after ${duration.toFixed(2)}ms`);

        document.getElementById('tasks-container').innerHTML = `
            <p class="no-tasks" style="color: #ef4444;">
                Failed to load tasks. Please check if the backend is running.
            </p>
        `;
        showToast('Failed to load tasks', 'error');
    }
}

// Render tasks
function renderTasks() {
    const container = document.getElementById('tasks-container');

    if (tasks.length === 0) {
        container.innerHTML = '<p class="no-tasks">No tasks yet. Create your first task above!</p>';
        return;
    }

    container.innerHTML = tasks
        .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
        .map(task => createTaskCard(task))
        .join('');
}

// Create task card HTML
function createTaskCard(task) {
    const createdDate = new Date(task.created_at).toLocaleString();

    return `
        <div class="task-card ${task.completed ? 'completed' : ''}" data-task-id="${task.id}">
            <div class="task-header">
                <div class="task-title">${escapeHtml(task.title)}</div>
            </div>
            ${task.description ? `<div class="task-description">${escapeHtml(task.description)}</div>` : ''}
            <div class="task-meta">
                <span class="task-timestamp">Created: ${createdDate}</span>
                <div class="task-actions">
                    <button
                        class="task-btn ${task.completed ? 'task-btn-incomplete' : 'task-btn-complete'}"
                        onclick="toggleTask(${task.id}, ${task.completed})"
                    >
                        ${task.completed ? 'Mark Incomplete' : 'Mark Complete'}
                    </button>
                    <button
                        class="task-btn task-btn-delete"
                        onclick="deleteTask(${task.id})"
                    >
                        Delete
                    </button>
                </div>
            </div>
        </div>
    `;
}

// Handle form submission
async function handleFormSubmit(e) {
    e.preventDefault();
    const startTime = performance.now();

    const titleInput = document.getElementById('task-title');
    const descriptionInput = document.getElementById('task-description');

    const title = titleInput.value.trim();
    const description = descriptionInput.value.trim();

    if (!title) {
        showToast('Task title is required', 'warning');
        return;
    }

    console.log('[TRACE] Creating new task:', { title, description });

    try {
        const response = await fetch(`${API_URL}/tasks`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Operation': 'create-task',
            },
            body: JSON.stringify({
                title,
                description,
                completed: false,
            }),
        });

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const newTask = await response.json();
        const duration = performance.now() - startTime;

        console.log(`[METRIC] Task created in ${duration.toFixed(2)}ms`);
        console.log('[TRACE] New task created:', newTask);

        tasks.push(newTask);
        renderTasks();
        updateStats();

        // Clear form
        titleInput.value = '';
        descriptionInput.value = '';

        showToast('Task created successfully', 'success');
    } catch (error) {
        console.error('[ERROR] Failed to create task:', error);
        const duration = performance.now() - startTime;
        console.log(`[METRIC] Task creation failed after ${duration.toFixed(2)}ms`);
        showToast('Failed to create task', 'error');
    }
}

// Toggle task completion
async function toggleTask(taskId, currentStatus) {
    const startTime = performance.now();
    console.log('[TRACE] Toggling task:', { taskId, currentStatus });

    try {
        const response = await fetch(`${API_URL}/tasks/${taskId}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'X-Operation': 'toggle-task',
            },
            body: JSON.stringify({
                completed: !currentStatus,
            }),
        });

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const updatedTask = await response.json();
        const duration = performance.now() - startTime;

        console.log(`[METRIC] Task toggled in ${duration.toFixed(2)}ms`);

        const index = tasks.findIndex(t => t.id === taskId);
        if (index !== -1) {
            tasks[index] = updatedTask;
        }

        renderTasks();
        updateStats();
        showToast(`Task marked as ${updatedTask.completed ? 'complete' : 'incomplete'}`, 'success');
    } catch (error) {
        console.error('[ERROR] Failed to toggle task:', error);
        const duration = performance.now() - startTime;
        console.log(`[METRIC] Task toggle failed after ${duration.toFixed(2)}ms`);
        showToast('Failed to update task', 'error');
    }
}

// Delete task
async function deleteTask(taskId) {
    const startTime = performance.now();
    console.log('[TRACE] Deleting task:', taskId);

    if (!confirm('Are you sure you want to delete this task?')) {
        return;
    }

    try {
        const response = await fetch(`${API_URL}/tasks/${taskId}`, {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
                'X-Operation': 'delete-task',
            },
        });

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const duration = performance.now() - startTime;
        console.log(`[METRIC] Task deleted in ${duration.toFixed(2)}ms`);

        tasks = tasks.filter(t => t.id !== taskId);
        renderTasks();
        updateStats();
        showToast('Task deleted successfully', 'success');
    } catch (error) {
        console.error('[ERROR] Failed to delete task:', error);
        const duration = performance.now() - startTime;
        console.log(`[METRIC] Task deletion failed after ${duration.toFixed(2)}ms`);
        showToast('Failed to delete task', 'error');
    }
}

// Update statistics
function updateStats() {
    const total = tasks.length;
    const completed = tasks.filter(t => t.completed).length;
    const pending = total - completed;

    document.getElementById('total-tasks').textContent = total;
    document.getElementById('completed-tasks').textContent = completed;
    document.getElementById('pending-tasks').textContent = pending;

    console.log('[METRIC] Stats updated:', { total, completed, pending });
}

// Testing functions
async function simulateError() {
    const startTime = performance.now();
    console.log('[TRACE] Simulating error');

    try {
        const response = await fetch(`${API_URL}/simulate-error`, {
            headers: {
                'X-Operation': 'simulate-error',
            },
        });

        const duration = performance.now() - startTime;
        console.log(`[METRIC] Error simulation request completed in ${duration.toFixed(2)}ms`);
        console.log(`[METRIC] Response status: ${response.status}`);

        showToast('Error simulation triggered - Check Grafana for traces!', 'warning');
    } catch (error) {
        console.error('[ERROR] Error simulation failed:', error);
        showToast('Check observability dashboards for error traces', 'warning');
    }
}

async function simulateSlowRequest() {
    const startTime = performance.now();
    console.log('[TRACE] Simulating slow request');
    showToast('Slow request started (2 seconds)...', 'warning');

    try {
        const response = await fetch(`${API_URL}/simulate-slow?delay=2`, {
            headers: {
                'X-Operation': 'simulate-slow',
            },
        });

        const duration = performance.now() - startTime;
        console.log(`[METRIC] Slow request completed in ${duration.toFixed(2)}ms`);

        if (response.ok) {
            showToast(`Slow request completed in ${(duration / 1000).toFixed(2)}s - Check Grafana!`, 'success');
        }
    } catch (error) {
        console.error('[ERROR] Slow request failed:', error);
        showToast('Slow request failed', 'error');
    }
}

async function createMultipleTasks() {
    console.log('[TRACE] Creating multiple tasks');
    showToast('Creating 5 bulk tasks...', 'warning');

    const taskPromises = [];

    for (let i = 1; i <= 5; i++) {
        const promise = fetch(`${API_URL}/tasks`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Operation': 'bulk-create',
            },
            body: JSON.stringify({
                title: `Bulk Task ${i}`,
                description: `This is bulk task number ${i} for testing observability`,
                completed: false,
            }),
        });
        taskPromises.push(promise);
    }

    try {
        const startTime = performance.now();
        await Promise.all(taskPromises);
        const duration = performance.now() - startTime;

        console.log(`[METRIC] Created 5 tasks in ${duration.toFixed(2)}ms`);
        await loadTasks();
        showToast('5 tasks created successfully - Check Grafana for traces!', 'success');
    } catch (error) {
        console.error('[ERROR] Failed to create bulk tasks:', error);
        showToast('Failed to create some tasks', 'error');
    }
}

// Toast notification
function showToast(message, type = 'success') {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.textContent = message;

    container.appendChild(toast);

    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => container.removeChild(toast), 300);
    }, 3000);
}

// Utility function to escape HTML
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Make functions globally available
window.toggleTask = toggleTask;
window.deleteTask = deleteTask;
window.simulateError = simulateError;
window.simulateSlowRequest = simulateSlowRequest;
window.createMultipleTasks = createMultipleTasks;
