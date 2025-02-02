# Swae

**Swae** is a live streaming application built on the [Nostr](https://nostr.com/) protocol, aiming to provide a censorship-resistant platform for content creators and viewers. Users are able to send bitcoin to streamers and other users over the lightning protocol.

## Table of Contents

- [Swae](#swae)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Installation](#installation)
  - [Usage](#usage)
  - [Contributing](#contributing)
  - [License](#license)

## Features

- **Decentralized Streaming**: Leverages the Nostr protocol to ensure streams are distributed across multiple relays, enhancing resilience and censorship resistance.
- **User-Controlled Data**: Empowers users to own and control their streaming content without reliance on centralized servers.
- **Real-Time Interaction**: Supports live chat and interactions between streamers and viewers.
- **Zaps**: Send bitcoin to streamers and other users over the lightning protocol.

## Installation

To set up the development environment for Swae, follow these steps:

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/suhailsaqan/swae.git
   cd swae
   ```

2. **Install Dependencies**:

   Ensure you have [Swift](https://swift.org/getting-started/) and [Xcode](https://developer.apple.com/xcode/) installed. Open the `swae.xcodeproj` file in Xcode and resolve any package dependencies.

3. **Build the Project**:

   Use Xcode to build and run the project on your preferred device or simulator.

## Usage

Once the application is running:

- **Create an Account**: Sign up using nostr.
- **Start Streaming**: Navigate to the streaming section and begin your live broadcast.
- **Join a Stream**: Browse available live streams and join to watch and interact.

For detailed instructions and troubleshooting, please refer to the [Nostr documentation](https://nostr.com/).

## Contributing

We welcome contributions from the community! To contribute:

1. Fork the repository.
2. Create a new branch (`git checkout -b feature-branch`).
3. Make your changes.
4. Commit your changes (`git commit -m 'Add new feature'`).
5. Push to the branch (`git push origin feature-branch`).
6. Open a Pull Request.

Please ensure your code adheres to the project's coding standards and includes appropriate tests.

## License

This project is licensed under the GPL-3.0 License. See the [LICENSE](LICENSE) file for details.

---