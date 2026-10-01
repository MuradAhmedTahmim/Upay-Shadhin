# upay Shadhin API — Hugging Face Space (Docker SDK)
#
# The dataset and the models are NOT committed to the repository: they are generated
# artifacts, reproducible from a fixed seed. So the image builds them during `docker
# build` rather than shipping 47 MB of CSV. That costs about three minutes once, and
# guarantees the running service and the published metrics come from exactly the code
# in this commit.

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY data/ ./data/
COPY ml/ ./ml/
COPY rules/ ./rules/
COPY nlg/ ./nlg/
COPY api/ ./api/

# Generate the synthetic data, train both models, and produce the holdout report, so
# /metrics serves numbers this build actually computed.
RUN python data/generate.py \
 && python -m ml.train \
 && python -m ml.evaluate

# Hugging Face Spaces route traffic to 7860.
EXPOSE 7860
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "7860"]
