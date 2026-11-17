import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { TopBar } from "@/components/top-bar";
import { FabGroup } from "@/components/fab-group";
import { ConvexClientProvider } from "@/components/convex-provider";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const emojiFavicon =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Ctext x='50%25' y='50%25' dominant-baseline='central' text-anchor='middle' font-size='48'%3E🏋️‍♂️%3C/text%3E%3C/svg%3E";

export const metadata: Metadata = {
  title: "OpenGym 🏋️‍♂️",
  description: "OpenGym – AI-powered workout companion",
  icons: {
    icon: emojiFavicon,
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="overflow-x-hidden">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased overflow-x-hidden`}
      >
        <ConvexClientProvider>
          <div className="flex h-[100dvh] flex-col overflow-hidden">
            <TopBar />
            <div className="flex-1 overflow-y-auto">
              {children}
            </div>
          </div>
          <FabGroup />
        </ConvexClientProvider>
      </body>
    </html>
  );
}
