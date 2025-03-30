FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5555
ENV FLASK_APP=shell_manager.py
ENV FLASK_ENV=production

CMD ["python", "shell_manager.py"]
