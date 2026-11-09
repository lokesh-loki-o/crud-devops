
import { useState, useEffect } from 'react'
import axios from 'axios'
import './App.css'

const API_URL = '/api/v1/tasks'

function App() {
  const [tasks, setTasks] = useState([])
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [editingId, setEditingId] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  // READ: Fetch all tasks
  const fetchTasks = async () => {
    try {
      setLoading(true)
      setError('')
      const response = await axios.get(API_URL)

      const data = response.data
      setTasks(Array.isArray(data) ? data : data.tasks || [])
    } catch (err) {
      setError('Unable to load tasks. Check whether Rails is running.')
      console.error(err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchTasks()
  }, [])

  // CREATE and UPDATE
  const handleSubmit = async (e) => {
    e.preventDefault()

    if (!title.trim()) {
      setError('Please enter a task title.')
      return
    }

    const taskData = {
      task: {
        title,
        description,
      },
    }

    try {
      setError('')

      if (editingId) {
        await axios.patch(`${API_URL}/${editingId}`, taskData)
      } else {
        await axios.post(API_URL, taskData)
      }

      setTitle('')
      setDescription('')
      setEditingId(null)
      await fetchTasks()
    } catch (err) {
      setError('Unable to save task. Check the Rails API.')
      console.error(err)
    }
  }

  // EDIT
  const handleEdit = (task) => {
    setTitle(task.title || '')
    setDescription(task.description || '')
    setEditingId(task.id)
    setError('')
  }

  // DELETE
  const handleDelete = async (id) => {
    if (!window.confirm('Are you sure you want to delete this task?')) {
      return
    }

    try {
      await axios.delete(`${API_URL}/${id}`)
      await fetchTasks()
    } catch (err) {
      setError('Unable to delete task.')
      console.error(err)
    }
  }

  // MARK COMPLETED
  const handleComplete = async (task) => {
    try {
      await axios.patch(`${API_URL}/${task.id}`, {
        task: {
          completed: !task.completed,
        },
      })
      await fetchTasks()
    } catch (err) {
      setError('Unable to update task status.')
      console.error(err)
    }
  }

  const cancelEdit = () => {
    setTitle('')
    setDescription('')
    setEditingId(null)
  }

  return (
    <div className="app">
      <header className="header">
        <h1>Task Manager</h1>
        <p>CRUD DevOps Project | React + Rails + MySQL</p>
      </header>

      <main className="container">
        <section className="form-card">
          <h2>{editingId ? 'Update Task' : 'Create New Task'}</h2>

          <form onSubmit={handleSubmit}>
            <input
              type="text"
              placeholder="Enter task title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
            />

            <textarea
              placeholder="Enter task description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              rows="4"
            />

            <div className="form-buttons">
              <button type="submit" className="primary-btn">
                {editingId ? 'Update Task' : 'Add Task'}
              </button>

              {editingId && (
                <button
                  type="button"
                  className="cancel-btn"
                  onClick={cancelEdit}
                >
                  Cancel
                </button>
              )}
            </div>
          </form>
        </section>

        <section className="tasks-section">
          <div className="section-heading">
            <h2>My Tasks</h2>
            <button onClick={fetchTasks} className="refresh-btn">
              Refresh
            </button>
          </div>

          {error && <p className="error">{error}</p>}

          {loading ? (
            <p>Loading tasks...</p>
          ) : tasks.length === 0 ? (
            <p className="empty">No tasks available. Add your first task!</p>
          ) : (
            <div className="task-list">
              {tasks.map((task) => (
                <div className="task-card" key={task.id}>
                  <div className="task-info">
                    <h3 className={task.completed ? 'completed' : ''}>
                      {task.title}
                    </h3>

                    <p>{task.description}</p>

                    <span
                      className={
                        task.completed
                          ? 'status completed-status'
                          : 'status pending-status'
                      }
                    >
                      {task.completed ? 'Completed' : 'Pending'}
                    </span>
                  </div>

                  <div className="task-actions">
                    <button
                      onClick={() => handleComplete(task)}
                      className="complete-btn"
                    >
                      {task.completed ? 'Undo' : 'Complete'}
                    </button>

                    <button
                      onClick={() => handleEdit(task)}
                      className="edit-btn"
                    >
                      Edit
                    </button>

                    <button
                      onClick={() => handleDelete(task.id)}
                      className="delete-btn"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      </main>
    </div>
  )
}

export default App
