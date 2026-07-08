# ── Stage 1: Builder ─────────────────────────────────────────────────────────
FROM cgr.dev/chainguard/python:latest-dev AS builder

WORKDIR /home/nonroot/app

# Chainguard runs as nonroot (UID 65532); build venv in a writable location
RUN python -m venv /home/nonroot/venv
ENV PATH="/home/nonroot/venv/bin:$PATH"

COPY requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# ── Stage 2: Runtime (Chainguard minimal — no shell, continuously patched) ───
FROM cgr.dev/chainguard/python:latest

WORKDIR /home/nonroot/app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH="/home/nonroot/app" \
    PATH="/home/nonroot/venv/bin:$PATH"

COPY --from=builder /home/nonroot/venv /home/nonroot/venv
COPY . ./

EXPOSE 8080

ENTRYPOINT ["python", "-m", "uvicorn", "conduit.app:app", "--host", "0.0.0.0", "--port", "8080"]
