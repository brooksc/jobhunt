import posthog from "posthog-js/dist/module.no-external";

const posthogProjectToken = process.env.POSTHOG_PROJECT_TOKEN;
const posthogHost = process.env.POSTHOG_HOST;
const isDevelopment = process.env.NODE_ENV === "development";

if (!posthogProjectToken || !posthogHost) {
  if (isDevelopment) {
    const missingVariable = !posthogProjectToken ? "POSTHOG_PROJECT_TOKEN" : "POSTHOG_HOST";
    throw new Error(
      `${missingVariable} variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once ${missingVariable} is configured`
    );
  }
} else {
  posthog.init(posthogProjectToken, {
    api_host: posthogHost,
    capture_exceptions: {
      capture_unhandled_errors: true,
      capture_unhandled_rejections: true,
      capture_console_errors: false,
    },
  });
}

globalThis.jobhuntPosthog = posthog;
