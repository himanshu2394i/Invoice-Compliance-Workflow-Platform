import asyncio
import logging
import os
from temporalio.client import Client
from temporalio.worker import Worker
from activities import extract_text_and_layout, ai_resolve_discrepancy, extract_document_header

async def main():
    logging.basicConfig(level=logging.INFO)

    # TEMPORAL_HOST lets this run unmodified both on the host machine (default
    # loopback) and inside docker-compose, where the Temporal service is reachable
    # by its service name instead of localhost.
    temporal_host = os.environ.get("TEMPORAL_HOST", "127.0.0.1:7233")
    client = await Client.connect(temporal_host)
    
    # Run the worker on the "ocr-tasks" queue
    worker = Worker(
        client,
        task_queue="ocr-tasks",
        activities=[extract_text_and_layout, ai_resolve_discrepancy, extract_document_header],
    )
    
    logging.info("Python LayoutLMv3 Worker started successfully. Listening on 'ocr-tasks' queue...")
    await worker.run()

if __name__ == "__main__":
    asyncio.run(main())
