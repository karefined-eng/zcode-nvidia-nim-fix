FROM python:3.11-slim
WORKDIR /app
COPY . /app
ENV PYTHONUNBUFFERED=1
EXPOSE 18787
CMD ["python", "-m", "nvidia_nim_proxy.server"]