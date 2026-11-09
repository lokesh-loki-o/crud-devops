class Api::V1::TasksController < ApplicationController
  # GET /api/v1/tasks
  def index
    @tasks = Task.all
    render json: @tasks
  end

  # GET /api/v1/tasks/:id
  def show
    @task = Task.find(params[:id])
    render json: @task
  end

  # POST /api/v1/tasks
  def create
    @task = Task.new(task_params)

    if @task.save
      render json: @task, status: :created
    else
      render json: { errors: @task.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/tasks/:id
  def update
    @task = Task.find(params[:id])

    if @task.update(task_params)
      render json: @task
    else
      render json: { errors: @task.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/tasks/:id
  def destroy
    @task = Task.find(params[:id])
    @task.destroy

    render json: { message: "Task deleted successfully" }
  end

  private

  def task_params
    params.require(:task).permit(:title, :description, :completed)
  end
end
