import { Space_Grotesk as SpaceGrotesk } from 'next/font/google';
import { Color } from '../styles/Color';

export const MAIN_FONT = SpaceGrotesk({
  subsets: ['latin'],
  variable: '--font-main',
  preload: true,
  fallback: ['sans-serif'],
});
export const APP_NAME = 'Open Intents Framework';
export const APP_DESCRIPTION = 'Intents For Everyone, With Everyone';
export const APP_URL = 'app.openintents.xyz';
export const BRAND_COLOR = Color.primary;
export const BACKGROUND_COLOR = Color.primary;
export const BACKGROUND_IMAGE =
  'url(/backgrounds/main.png), radial-gradient(circle at 50% -50%, rgba(0, 0, 0, 0), rgba(18, 28, 66, 0.8) 40%, rgb(18 28 66) 60%)';
