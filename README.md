<div align="center">

# 🩺 PATHCARE AI

### AI-Powered Smart Pathology Assistant using RAG + Flutter + Supabase

[![Flutter](https://img.shields.io/badge/Flutter-3.32-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.8-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Supabase](https://img.shields.io/badge/Supabase-Backend-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Database-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org)
[![Gemini](https://img.shields.io/badge/Gemini-2.5_Flash-4285F4?style=for-the-badge&logo=google&logoColor=white)](https://ai.google.dev)
[![pgvector](https://img.shields.io/badge/pgvector-Vector_DB-0F766E?style=for-the-badge&logo=postgresql&logoColor=white)](https://github.com/pgvector/pgvector)
[![Tesseract OCR](https://img.shields.io/badge/Tesseract-OCR-5C2D91?style=for-the-badge&logo=tesseract&logoColor=white)](https://tesseract-ocr.github.io)
[![OpenStreetMap](https://img.shields.io/badge/OpenStreetMap-Maps-7EBC6F?style=for-the-badge&logo=openstreetmap&logoColor=white)](https://www.openstreetmap.org)
[![flutter_map](https://img.shields.io/badge/flutter__map-Renderer-009688?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter-map.dev)
[![Geolocator](https://img.shields.io/badge/Geolocator-Location-10B981?style=for-the-badge&logo=googlemaps&logoColor=white)](https://pub.dev/packages/geolocator)
[![Cloudflare Pages](https://img.shields.io/badge/Cloudflare-Pages-F38020?style=for-the-badge&logo=cloudflare&logoColor=white)](https://pages.cloudflare.com)
[![Supabase Auth](https://img.shields.io/badge/Supabase-Auth-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)

### 🌐 Live Demo
**https://72ed0367.pathcare-ai.pages.dev/**

### 📱 APK
[![Download APK](https://img.shields.io/badge/PathCare_APK-34A853?style=for-the-badge&logo=android&logoColor=white)](https://github.com/yashbhandari0929/IQOO_PathCare/releases/download/v1.0.0/PathCare.apk)

</div>

---

# 📖 Overview

**Problem Statement**

Modern healthcare systems often face fragmented patient records, complex pathology reports that are difficult for patients to understand, delayed clinical decision-making, and limited access to immediate medical guidance and emergency blood resources. These challenges increase anxiety, reduce healthcare efficiency, and make quality medical assistance less accessible.

**Our Solution**

PATHCARE AI is an AI-powered cross-platform healthcare platform that leverages Retrieval-Augmented Generation (RAG), Gemini 2.5 Flash, Flutter, and Supabase to simplify pathology report analysis and healthcare workflows. The application automatically extracts and analyzes medical reports using OCR, provides context-aware AI assistance through a medical chatbot, enables secure role-based dashboards for Patients, Doctors, and Administrators, and offers a live blood bank locator using OpenStreetMap. By combining intelligent report interpretation with secure cloud infrastructure, PATHCARE AI improves accessibility, reduces manual effort, and supports faster, more informed healthcare decisions.

### ✨ Key Features

- 👤 Role-based authentication (Patient / Doctor / Admin)
- 🤖 AI Medical Report Analysis
- 💬 Context-aware Medical Chatbot (RAG)
- 📄 OCR-based pathology report processing
- 🧠 Semantic search using vector embeddings
- 🩸 Nearby Blood Bank Locator (OpenStreetMap)
- 📊 Doctor & Admin dashboards
- ☁️ Cloud-based report storage

---

# 🚀 Live Product

| Platform | Link |
|----------|------|
| 🌐 Web | https://72ed0367.pathcare-ai.pages.dev/ |
| 📱 Android | [PathCare APK](https://github.com/yashbhandari0929/IQOO_PathCare/releases/download/v1.0.0/PathCare.apk) |

---

# 👨‍💻 Team

| Name | Role |
|------|------|
| **Yash Bhandari** | Flutter & AI Integration |
| **Ayush** | Backend & Database |
| **Taranveer** | RAG, OCR & Testing |

---

# 🏗️ System Architecture

## RAG Workflow

```text
Medical Report
      │
      ▼
  OCR (Tesseract)
      │
      ▼
 Text Chunking
      │
      ▼
text-embedding-004
      │
      ▼
Supabase + pgvector
      │
      ▼
Semantic Retrieval
      │
      ▼
Retrieved Context
      │
      ▼
 Gemini 2.5 Flash
      │
      ├────────► AI Report Analysis
      │
      └────────► Medical Chatbot
```

---

# 🧩 Technology Stack

## Proprietary / Cloud Technologies

| Layer | Technology |
|--------|------------|
| Frontend | Flutter, Dart |
| Backend | Supabase |
| Database | PostgreSQL |
| AI / LLM | Gemini 2.5 Flash |
| Embeddings | Google text-embedding-004 |
| Authentication | Supabase Auth |
| Cloud Storage | Supabase Storage |
| Deployment | Cloudflare Pages |

## Open Source Technologies

| Layer | Technology |
|--------|------------|
| Vector Database | pgvector |
| OCR Engine | Tesseract OCR |
| Maps | OpenStreetMap |
| Map Renderer | flutter_map |
| Location | Geolocator |

---

# 📂 Project Structure

```text
pathcare-ai/
│
├── android/
├── ios/
├── web/
│
├── lib/
│   ├── config/
│   │    └── env_config.dart
│   │
│   ├── models/
│   ├── services/
│   │    ├── gemini_rag_service.dart
│   │    ├── ocr_service.dart
│   │    ├── blood_bank_service.dart
│   │    └── auth_service.dart
│   │
│   ├── screens/
│   │    ├── patient/
│   │    ├── doctor/
│   │    ├── admin/
│   │    └── auth/
│   │
│   ├── widgets/
│   └── main.dart
│
├── assets/
│   ├── images/
│   ├── icons/
│   └── reports/
│
├── apk/
│   └── PathCareAI.apk
│
└── README.md
```

---

# ⚙️ How to Run

## 1. Clone Repository

```bash
git clone https://github.com/your-username/pathcare-ai.git
cd pathcare-ai
```

## 2. Install Packages

```bash
flutter pub get
```

## 3. Configure Environment

Create:

```text
lib/config/env_config.dart
```

Paste:

```dart
class EnvConfig {
  static const String supabaseUrl = "YOUR_SUPABASE_URL";
  static const String supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY";
  static const String geminiApiKey = "YOUR_GEMINI_API_KEY";
}
```

> Keep this file out of Git using `.gitignore`.

## 4. Run Application

### Android

```bash
flutter run
```

### Web

```bash
flutter run -d chrome
```

### Production Build

```bash
flutter build web --release
```

Supabase Flutter is initialized using the project URL and publishable key in `main.dart`, following the official setup. <Cite ref={["turn0search2","turn0search5"]}/>

---

# 🔐 Demo Login Credentials

## 👤 Patient

| Email | Password |
|------|----------|
| `ybtest978@gmail.com` | `123456` |
| `user@gmail.com` | `user1234` |

---

## 🩺 Doctor

| Email | Password |
|------|----------|
| `doctor@gmail.com` | `doctor1234` |

---

## 👨‍💼 Admin

| Email | Password |
|------|----------|
| `admin@gmail.com` | `admin1234` |

---

# 📱 Application Modules

### Patient

- Upload pathology reports
- AI report analysis
- Medical chatbot
- Blood bank locator
- View medical history

### Doctor

- View assigned patients
- Analyze reports
- Manage consultations
- Dashboard analytics

### Admin

- User management
- Doctor management
- System analytics
- Hospital administration

---

# 🧠 AI Features

### AI Report Analysis

- OCR text extraction
- Intelligent summarization
- Key findings
- Abnormal parameter detection
- Medical recommendations

### Medical Chatbot

- Context-aware responses
- RAG-powered retrieval
- Uses previous report context
- Hallucination reduction via retrieved knowledge

---

# 🩸 Blood Bank Module

- Live OpenStreetMap integration
- Hospital-centered search
- Nearby blood bank discovery
- Call / WhatsApp / SMS support
- Radius-based visualization

---

# 🔒 Security

- Supabase Authentication
- Role-based access control
- PostgreSQL Row Level Security (RLS)
- Secure cloud storage
- Environment-based API key management

---

# 📊 Future Scope

- AI Appointment scheduling
- Voice-enabled AI assistant
- Multi-language support
- Wearable health integration

---

<div align="center">

### ⭐ If you like this project, give it a star!

**Made with ❤️ by Yash, Ayush & Taranveer**

</div>
