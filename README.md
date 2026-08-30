# Universal Medical AI Chatbot & Hospital App

A comprehensive Flutter application designed to bridge the gap between patients, doctors, and hospital administrators. Powered by a Gemini-backed Medical RAG Agent, the app features an intelligent chatbot capable of analyzing patient reports (via local OCR) and answering general health queries, all while strictly adhering to medical safety guidelines.

## Features

* **Intelligent Chatbot (Medical RAG)**: Answers general healthcare queries and uses local Google ML Kit OCR combined with Gemini to analyze medical reports and lab results.
* **Role-Based Access**: 
  * **Patients**: View reports, manage profiles, book appointments, and interact with the AI assistant.
  * **Doctors**: View queues, access clinical analytics, and analyze patient history trends.
  * **Admins/Supervisors**: Oversee hospital operations and access analytics.
* **Floor Navigation**: Interactive SVG floor maps and dynamic queue/ETA routing algorithms for in-hospital patient navigation.
* **Secure Backend**: Real-time Supabase PostgreSQL backend with authentication and encrypted cloud storage for medical records.

## Tech Stack

* **Frontend**: Flutter / Dart
* **Backend**: Supabase (Auth, Postgres, Storage)
* **AI Provider**: Google Gemini (gemini-3.6-flash & text-embedding-004)
* **OCR engine**: Google ML Kit & pdfx

## Folder Structure

```
lib/
 ├── config/       # API configuration and constants
 ├── models/       # Data models and entities
 ├── services/     # AI, navigation, booking, and doctor backend logic
 ├── screens/      # UI screens organized by user role
 │    ├── patient/
 │    ├── doctor/
 │    ├── admin/
 │    └── supervisor/
 ├── widgets/      # Reusable UI components
 ├── utils/        # Helper functions
 └── main.dart     # Application entry point
```

## Installation & Setup

1. **Clone the repository**
2. **Install dependencies**: 
   ```bash
   flutter pub get
   ```
3. **Set up Environment Variables**: Create a `.env` file in the root directory containing:
   ```env
   SUPABASE_URL=your_supabase_url
   SUPABASE_ANON_KEY=your_supabase_anon_key
   GEMINI_API_KEY=your_gemini_api_key
   ```
4. **Supabase Setup**: 
   Ensure your Supabase project contains the necessary tables (patients, doctors, appointments, chat_history, etc.) and `pgvector` enabled for semantic chunk matching.
5. **Run the App**: 
   ```bash
   flutter run
   ```

## Screenshots

*(Placeholder for screenshots of Chatbot, Dashboards, and Floor Map)*

## License

MIT License
