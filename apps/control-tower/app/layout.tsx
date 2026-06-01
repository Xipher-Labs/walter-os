import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Walter Council — Control Tower",
  description: "Real-time ops dashboard for the Walter Council multi-agent system",
};

// D-1: dark-mode-first. The operator runs this at night, so `.dark` is the
// default applied theme on <html> (not a prefers-color-scheme fallback). Light
// is opt-out by replacing the class with `.light`. The class is set
// server-side so there is no flash of the wrong theme on first paint.
export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`dark ${geistSans.variable} ${geistMono.variable} h-full`}
    >
      <body className="min-h-full flex flex-col bg-background text-foreground">
        {children}
      </body>
    </html>
  );
}
