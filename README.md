# gpt_read: A Document Analysis and Question Answering Framework

gpt_read is a versatile tool that leverages GPT models to answer questions based on document content. It is designed to process documents, extract key information, and generate responses tailored to user queries.

## Overview

The repository implements several strategies for document processing, including direct text retrieval, chunk-based processing, semantic segmentation, hierarchical summarization, and multi-pass refinement. These approaches allow users to choose a method that best fits the document type and question complexity.

## Key Features

- **Multiple Processing Methods:**  
  Supports various strategies such as retrieval, chunking, semantic analysis, hierarchical summarization, and combined multi-pass approaches, giving users flexibility in handling diverse document types.

- **Broad Format Support:**  
  Works with PDFs, DOCX, TXT, and images (with OCR), making it applicable across a wide range of document formats.

- **Efficiency and Accuracy:**  
  Automates the extraction of relevant content, reducing manual review time while enabling users to compare different methods to achieve the best results.

- **Scalability:**  
  Incorporates parallel processing and dynamic chunking, ensuring it can manage documents of varying sizes and complexities.

## How It Works

The system reads and processes documents by splitting them into manageable segments. It then applies the selected processing strategy to extract and synthesize the information needed to answer the user's query. The result is an answer that reflects the key content of the document, with options for further refinement.

## Prerequisites

This system assumes you have a valid API key with OpenAI. To obtain an API key:
- Visit [OpenAI's API page](https://openai.com/api/).
- Register for an account and follow the instructions to generate your API key.
- Configure your environment to use this key as required by the system.

## Getting Started

1. **Select Your Document(s):**  
   Place your document in the designated folder. Supported formats include PDF, DOCX, TXT, and images (with OCR).

2. **Select a Processing Method:**  
   Choose from one of the available strategies based on your document and the nature of your question.

3. **Submit Your Query:**  
   Use the provided functions to ask a question. The system will process the document and return a generated answer.

This framework offers a clear, systematic approach to document analysis, enabling efficient extraction of relevant information from a variety of sources.
