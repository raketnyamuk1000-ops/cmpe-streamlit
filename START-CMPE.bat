import os
import re
import io
import json
import requests
import streamlit as st
from datetime import datetime

# Safe import for export libraries
try:
    from docx import Document
    HAS_DOCX = True
except ImportError:
    HAS_DOCX = False

try:
    from fpdf import FPDF
    HAS_FPDF = True
except ImportError:
    HAS_FPDF = False

try:
    import ebooklib
    from ebooklib import epub
    HAS_EPUB = True
except ImportError:
    HAS_EPUB = False

# Safe import for Google Gemini SDK
try:
    import google.generativeai as genai
    HAS_GEMINI = True
except ImportError:
    HAS_GEMINI = False

# ==========================================
# PAGE CONFIGURATION
# ==========================================
st.set_page_config(
    page_title="CMPE v6.0 - Master Publishing Engine",
    page_icon="⛪",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Initialize session state
if "current_step" not in st.session_state:
    st.session_state["current_step"] = "Input"
if "master_manuscript" not in st.session_state:
    st.session_state["master_manuscript"] = ""
if "sermon_topic" not in st.session_state:
    st.session_state["sermon_topic"] = ""

# ==========================================
# SYSTEM PROMPT
# ==========================================
SYSTEM_PROMPT = """You are a master theologian and professional publishing editor creating a definitive MASTER MANUSCRIPT.

CRITICAL RULES:
1. Use DIRECT "YOU" language throughout.
2. Open with RAW TENSION and human struggle.
3. Tell complete stories with sensory details, emotional stakes, dialogue.
4. Unpack Scriptures line-by-line using mechanical exegesis.
5. Address doubts directly with 3-Stage Resolution.
6. Include explicit "What if you've already failed?" Grace Protocol.
7. Include 3-5 concrete action steps.
8. NEVER use bracketed audio cues like [PAUSE] or [SLOW]."""

# ==========================================
# TRANSFORMATION ENGINES
# ==========================================

def transform_for_kindle(text: str) -> str:
    lines = text.split('\n')
    kindle_lines = []
    for line in lines:
        if line.startswith('#') or line.startswith('>') or line.startswith('|') or not line.strip():
            kindle_lines.append(line)
        else:
            sentences = re.split(r'(?<=[.!?]) +', line)
            chunk = ""
            for s in sentences:
                if len(chunk) + len(s) > 120:
                    kindle_lines.append(chunk.strip())
                    kindle_lines.append("")
                    chunk = s
                else:
                    chunk += " " + s if chunk else s
            if chunk:
                kindle_lines.append(chunk.strip())
                kindle_lines.append("")
    return "\n".join(kindle_lines)

def transform_for_paperback(text: str) -> str:
    paragraphs = text.split('\n\n')
    paperback_paragraphs = []
    for p in paragraphs:
        cleaned = p.strip()
        if cleaned.startswith('#'):
            paperback_paragraphs.append(cleaned)
        elif cleaned.startswith('>'):
            paperback_paragraphs.append(f"*{cleaned}*")
        else:
            merged = " ".join([line.strip() for line in cleaned.split('\n') if line.strip()])
            paperback_paragraphs.append(merged)
    paperback_paragraphs.append("\n\n---\n\n### Reflection Questions\n1. What challenge resonates most?\n2. How does the exegesis challenge your understanding?\n3. What action step will you implement?\n4. What questions remain?")
    return "\n\n".join(paperback_paragraphs)

def transform_for_pdf(text: str) -> str:
    scripture_refs = list(set(re.findall(r'[A-Za-z]+\s+\d+:\d+', text)))
    sections = re.split(r'(?=#+ )', text)
    pdf_optimized = ["# REFERENCE & STUDY GUIDE EDITION", "*Optimized for printouts and group study.*\n\n---\n"]
    if scripture_refs:
        pdf_optimized.append("## Key Scriptures")
        for ref in scripture_refs[:5]:
            pdf_optimized.append(f"- **{ref}**")
        pdf_optimized.append("\n---\n")
    for section in sections:
        if not section.strip():
            continue
        if section.startswith('#'):
            pdf_optimized.append(f"\n{section}\n")
        else:
            for p in section.split('\n\n'):
                if p.strip():
                    highlighted = re.sub(r'"([^"]+)"', r'**"\1"**', p)
                    pdf_optimized.append(highlighted)
                    pdf_optimized.append('')
    pdf_optimized.extend([
        "\n---\n", "## Group Discussion Worksheet\n",
        "### Part A: Scripture Observation\n1. Primary Scripture: _______________\n2. Key word in original language: _______________\n3. What does this reveal about God's character? _______________\n",
        "### Part B: Personal Reflection\n4. What tension mirrors your situation? _______________\n5. How does this challenge your assumptions? _______________\n",
        "### Part C: Action Plan\n6. One concrete action step: _______________\n7. Timeline: _______________\n8. Accountability partner: _______________\n"
    ])
    return '\n'.join(pdf_optimized)

def transform_for_audiobook(text: str) -> str:
    audio_optimized = [
        "Welcome. I'm glad you're here.",
        "Let's talk about something that affects every one of us.",
        "This isn't a lecture - it's a conversation.\n"
    ]
    cleaned = text
    cleaned = re.sub(r'#+\s*(.*?)\n', r'\nLet\'s explore \1...\n', cleaned)
    cleaned = re.sub(r'[*_`~]', '', cleaned)
    cleaned = re.sub(r'\|.*?\|', '', cleaned)
    cleaned = re.sub(r'^\s*-\s+', 'First, ', cleaned, flags=re.MULTILINE)
    cleaned = re.sub(r'^\s*\d+\.\s+', 'Another point is ', cleaned, flags=re.MULTILINE)
    cleaned = re.sub(r'see the diagram below', 'as we consider this together', cleaned)
    cleaned = re.sub(r'refer to page \d+', 'as I mentioned earlier', cleaned)
    paragraphs = cleaned.split('\n\n')
    verbal_paragraphs = []
    for i, p in enumerate(paragraphs):
        if not p.strip():
            continue
        if i == 0:
            p = f"Think about this. {p.strip()}"
        elif i % 3 == 0:
            p = f"Now here's something important. {p.strip()}"
        elif i % 2 == 0:
            p = f"You might be wondering about this next part. {p.strip()}"
        else:
            p = f"Let me share one more thought. {p.strip()}"
        verbal_paragraphs.append(p)
    audio_optimized.extend(verbal_paragraphs)
    audio_optimized.extend([
        "\n\nAs we wrap up...", "This isn't the end - it's just the beginning.",
        "Thanks for listening.", "*End of Audio Recording.*"
    ])
    return '\n\n'.join(audio_optimized)

# ==========================================
# EXPORT GENERATORS
# ==========================================
def convert_to_docx(text, title):
    doc = Document()
    doc.add_heading(title, level=0)
    for line in text.split('\n'):
        if line.startswith('## '):
            doc.add_heading(line.replace('## ', ''), level=1)
        elif line.startswith('### '):
            doc.add_heading(line.replace('### ', ''), level=2)
        elif line.strip():
            doc.add_paragraph(line)
    buffer = io.BytesIO()
    doc.save(buffer)
    return buffer.getvalue()

def convert_to_pdf_bytes(text, title):
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", size=11)
    clean_text = text.encode('latin-1', 'replace').decode('latin-1')
    pdf.multi_cell(0, 8, clean_text)
    return pdf.output()

def convert_to_epub_bytes(text, title):
    book = epub.EpubBook()
    book.set_title(title)
    book.set_language('en')
    html_content = text.replace('\n', '<br/>')
    c1 = epub.EpubHtml(title='Edition', file_name='edition.xhtml', lang='en')
    c1.content = f'<h1>{title}</h1><p>{html_content}</p>'
    book.add_item(c1)
    book.toc = (epub.Link('edition.xhtml', 'Edition', 'edition'),)
    book.add_item(epub.EpubNcx())
    book.add_item(epub.EpubNav())
    book.spine = ['nav', c1]
    buffer = io.BytesIO()
    epub.write_epub(buffer, book)
    return buffer.getvalue()

# ==========================================
# API DISPATCHER
# ==========================================
def fetch_api_key(key_name):
    if os.getenv(key_name): return os.getenv(key_name)
    if key_name in st.secrets: return st.secrets[key_name]
    return ""

def call_llm(provider, model_name, prompt, system_prompt=""):
    full_prompt = f"{system_prompt}\n\n{prompt}" if system_prompt else prompt

    if provider == "Groq (Free Tier)":
        api_key = fetch_api_key("GROQ_API_KEY")
        if not api_key: raise ValueError("GROQ_API_KEY missing.")
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        payload = {
            "model": model_name or "llama-3.3-70b-versatile",
            "messages": [{"role": "system", "content": system_prompt}, {"role": "user", "content": prompt}],
            "temperature": 0.7
        }
        res = requests.post("https://api.groq.com/openai/v1/chat/completions", headers=headers, json=payload)
        if res.status_code != 200: raise Exception(f"Groq Error: {res.text}")
        return res.json()['choices'][0]['message']['content']

    elif provider == "Google Gemini":
        api_key = fetch_api_key("GEMINI_API_KEY")
        if not api_key: raise ValueError("GEMINI_API_KEY missing.")
        if HAS_GEMINI:
            genai.configure(api_key=api_key)
            model = genai.GenerativeModel('gemini-1.5-pro', system_instruction=system_prompt)
            return model.generate_content(prompt).text
        else:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key={api_key}"
            res = requests.post(url, json={"contents": [{"parts": [{"text": full_prompt}]}]})
            return res.json()['candidates'][0]['content']['parts'][0]['text']

    elif provider == "OpenRouter":
        api_key = fetch_api_key("OPENROUTER_API_KEY")
        if not api_key: raise ValueError("OPENROUTER_API_KEY missing.")
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        payload = {
            "model": model_name or "meta-llama/llama-3.3-70b-instruct",
            "messages": [{"role": "system", "content": system_prompt}, {"role": "user", "content": prompt}],
            "temperature": 0.7
        }
        res = requests.post("https://openrouter.ai/api/v1/chat/completions", headers=headers, json=payload)
        return res.json()['choices'][0]['message']['content']

# ==========================================
# SIDEBAR NAV
# ==========================================
st.sidebar.markdown("### Pipeline Progress")
steps = ["Input", "Research", "Blueprint", "Scripture", "Master Script", "4-Format Engine"]
for s in steps:
    if s == st.session_state["current_step"]:
        st.sidebar.markdown(f"🔵 **{s}**")
    elif steps.index(s) < steps.index(st.session_state["current_step"]):
        st.sidebar.markdown(f"✅ **{s}**")
    else:
        st.sidebar.markdown(f"⬜ **{s}**")

st.sidebar.markdown("---")
st.sidebar.markdown("### Provider")
provider = st.sidebar.selectbox("API Provider", ["Groq (Free Tier)", "Google Gemini", "OpenRouter"])

if provider == "Groq (Free Tier)":
    selected_model = st.sidebar.selectbox("Groq Model", ["llama-3.3-70b-versatile", "llama3-8b-8192"])
elif provider == "Google Gemini":
    selected_model = st.sidebar.selectbox("Gemini Model", ["gemini-1.5-pro", "gemini-1.5-flash"])
else:
    selected_model = st.sidebar.selectbox("OpenRouter Model", ["meta-llama/llama-3.3-70b-instruct", "anthropic/claude-3.5-sonnet"])

# ==========================================
# MAIN VIEWS
# ==========================================
st.title("Christian Media Production Engine")
st.caption("Ver 6.0 | Master Manuscript to 4 Reading Experiences Engine")

if st.session_state["current_step"] == "Input":
    st.subheader("Step 1: Define Master Manuscript Parameters")
    c1, c2 = st.columns(2)
    with c1:
        topic = st.text_input("Sermon Topic", value="Honoring Their Mother and Father")
        scripture = st.text_input("Scripture Reference", value="Exodus 20:12")
    with c2:
        length = st.selectbox("Length", ["Short (~6 min)", "Medium (~10 min)", "Long (~15 min)"])
        lens = st.selectbox("Theological Lens", ["non_denominational", "Reformed", "Pentecostal", "Catholic", "Baptist"])
    c3, c4 = st.columns(2)
    with c3:
        audience = st.selectbox("Target Audience", ["Young Adults", "Mixed", "Seniors", "Children"])
        style = st.selectbox("Preaching Style", ["Narrative", "Expository", "Topical", "Prophetic"])
    with c4:
        cultural = st.text_input("Cultural Hook (optional)", value="Cancellation culture")
        story = st.text_input("Figure / Story (optional)", value="Auguste Rodin")
    context = st.text_area("Context Notes (optional)", height=100)

    st.markdown("---")
    if st.button("Process Master Manuscript"):
        if not topic or not scripture:
            st.error("Please fill in both Sermon Topic and Scripture Reference.")
        else:
            with st.spinner("Writing Master Manuscript..."):
                try:
                    user_prompt = f"Topic: {topic}, Scripture: {scripture}, Audience: {audience}, Style: {style}, Story: {story}, Cultural: {cultural}"
                    sermon = call_llm(provider, selected_model, user_prompt, SYSTEM_PROMPT)
                    st.session_state["master_manuscript"] = sermon
                    st.session_state["sermon_topic"] = topic
                    st.session_state["current_step"] = "Master Script"
                    st.rerun()
                except Exception as e:
                    st.error(f"Error: {e}")

elif st.session_state["current_step"] == "Master Script":
    st.subheader("Step 2: Review Master Manuscript")
    st.markdown(st.session_state["master_manuscript"])
    st.markdown("---")
    c1, c2 = st.columns([1, 1])
    with c1:
        if st.button("Back to Input"):
            st.session_state["current_step"] = "Input"
            st.rerun()
    with c2:
        if st.button("Proceed to 4-Format Engine"):
            st.session_state["current_step"] = "4-Format Engine"
            st.rerun()

elif st.session_state["current_step"] == "4-Format Engine":
    st.subheader("Step 3: Four Reading Experiences Engine")
    topic_slug = st.session_state["sermon_topic"].lower().replace(" ", "_") or "sermon"
    master = st.session_state["master_manuscript"]
    title = st.session_state["sermon_topic"] or "Sermon Script"

    kindle_version = transform_for_kindle(master)
    paperback_version = transform_for_paperback(master)
    pdf_version = transform_for_pdf(master)
    audio_version = transform_for_audiobook(master)

    tabs = st.tabs(["Kindle Edition", "Paperback Edition", "PDF Reference Edition", "Audiobook Script"])

    with tabs[0]:
        st.markdown("### Kindle Edition")
        st.text_area("Kindle Preview", value=kindle_version, height=250)
        if HAS_EPUB:
            st.download_button("Download Kindle (.epub)", data=convert_to_epub_bytes(kindle_version, title), file_name=f"{topic_slug}_kindle.epub", mime="application/epub+zip")
        else:
            st.warning("ebooklib not installed. Run: pip install EbookLib")

    with tabs[1]:
        st.markdown("### Paperback Edition")
        st.text_area("Paperback Preview", value=paperback_version, height=250)
        if HAS_DOCX:
            st.download_button("Download Paperback (.docx)", data=convert_to_docx(paperback_version, title), file_name=f"{topic_slug}_paperback.docx", mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document")
        else:
            st.warning("python-docx not installed. Run: pip install python-docx")

    with tabs[2]:
        st.markdown("### PDF Reference Edition")
        st.text_area("PDF Preview", value=pdf_version, height=250)
        if HAS_FPDF:
            st.download_button("Download PDF Study Guide (.pdf)", data=bytes(convert_to_pdf_bytes(pdf_version, title)), file_name=f"{topic_slug}_study_guide.pdf", mime="application/pdf")
        else:
            st.warning("fpdf2 not installed. Run: pip install fpdf2")

    with tabs[3]:
        st.markdown("### Audiobook Script Edition")
        st.text_area("Audio Script Preview", value=audio_version, height=250)
        st.download_button("Download Audio Script (.md)", data=audio_version, file_name=f"{topic_slug}_audio_script.md", mime="text/markdown")

    st.markdown("---")
    if st.button("Return to Master Manuscript"):
        st.session_state["current_step"] = "Master Script"
        st.rerun()