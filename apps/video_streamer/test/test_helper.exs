# Configure logger to suppress warnings and errors during tests
# This prevents noisy camera initialization errors when running on development machines
Logger.configure(level: :error)

# Alternatively, you can completely silence logs during tests:
# Logger.configure(level: :none)

ExUnit.start()
