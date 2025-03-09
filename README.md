# gpt_read
This repository contains several R scripts that implement document processing and question answering using GPT models. Each script provides functions for different processing modes and text handling techniques. Below is a summary of each function grouped by file.

## chunked_mode.R

- **gpt_read_chunked**  
  Splits a document into text chunks and queries each chunk with a specified question using GPT.  
  - **Key Features:**  
    - Handles oversized chunks by further splitting them if needed.  
    - Supports parallel processing for querying chunks.  
    - Merges individual responses into one consolidated final answer.

## hierarchical_mode.R

- **gpt_read_hierarchical**  
  Implements a two-pass strategy where each chunk is first summarized with respect to the question.  
  - **Key Features:**  
    - Summarizes each chunk to extract relevant information.  
    - Combines the summaries into a final detailed answer.  
    - Option to run summaries in parallel.

## main.R

- **answer_question**  
  A high-level orchestration function that directs the document processing workflow.  
  - **Key Features:**  
    - Supports multiple modes: Retrieval, Chunked, Semantic, Hierarchical, and MultiPass.  
    - Parses the document and splits it into chunks based on the selected mode.  
    - Optionally refines the final answer for accuracy and completeness.

## multi_pass_mode.R

- **refine_answer**  
  Improves an existing answer by reconsulting the document.  
  - **Key Features:**  
    - Extracts key excerpts from the document using keyword searches.  
    - Uses GPT to refine the answer based on the extracted text.
  
- **gpt_read_multipass**  
  Combines retrieval and chunked strategies to generate a more comprehensive answer.  
  - **Key Features:**  
    - Executes both retrieval-based and chunked approaches.  
    - Merges the two answers into one final response using GPT.

## packages.R

- **Package Installation and Loading**  
  Checks for and installs any missing required R packages before loading them silently.  
  - **Key Features:**  
    - Ensures that all necessary packages (e.g., shiny, future, pdftools, tesseract) are installed.  
    - Loads packages in a way that suppresses startup messages.

## retrieval_mode.R

- **search_text**  
  Searches for keywords within the text and extracts surrounding context snippets.  
  - **Key Features:**  
    - Returns unique passages containing the specified keywords.
  
- **gpt_read_retrieval**  
  Uses a keyword-based retrieval approach to extract relevant text sections before querying GPT.  
  - **Key Features:**  
    - Consolidates document text and ensures the content fits within the model's context window.  
    - Falls back to chunked mode if the document is too large or no relevant text is found.

## text_processing.R

- **filter_text**  
  Cleans the raw extracted text by removing irrelevant or boilerplate content.  
  - **Key Features:**  
    - Eliminates page numbers, figure/table captions, URLs, emails, and reference sections.
  
- **chunk_text_naive**  
  Splits the cleaned text into chunks based on paragraphs while respecting a token limit.  
  - **Key Features:**  
    - Combines paragraphs until the token count reaches the specified limit.
  
- **chunk_text_semantic**  
  Splits text into chunks by grouping semantically related paragraphs together.  
  - **Key Features:**  
    - Uses word overlap as a simple proxy for semantic similarity.
  
- **parse_text**  
  Reads and processes document files (supports PDF, DOCX, TXT, and images).  
  - **Key Features:**  
    - Applies OCR for scanned PDFs and image files.  
    - Cleans text using `filter_text` and splits it into chunks using either naive or semantic methods.  
    - Caches the parsed text to optimize repeated access.
