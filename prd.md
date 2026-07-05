# Mac Utility App for adding cards to a Planka board

This is a companion app for users who use Planka for managing scrum, kanban, or just their person to do list. The purpose of the app is to live in Mac menu bar and provide users with a menu option and a keyboard shortcut to add a card to a board.

## Requirements

- The app should be able to launch at startup. It should reuse session information from the last login to make sure it's logged in to the planka instance.
- The app should have a menu that includes "Create new card", "Settings", and "Quit".
- The app Settings should include:

  - URL for planka installation
  - Login (to establish a session)
  - Default Project (prepopulated with a list of projects)
  - Default Board (prepopulated list)
  - Default Label (prepopulated list or None)
  - Keyboard shortcut
  - Launch at startup radio button to enable or disable startup

- The app should request whatever security permissions are required (if any) to allow a global keyboard shortcut,
- The pop up when "create new card" is triggered should have:

  - Text box for typing the title
  - Project (populated with the default, prepopulated drop down list)
  - Board (populated with the default, prepopulated drop down list)
  - Label (populated with the default, prepopulated drop down list)
  - Enter sends the card to Planka

- The login page should use a browser to login to planka or alternatively if provided for by the API, a username and password input field.
- The app's menubar icon should be stylized the Planka icon.
- The app should be self-signed
- The app should have error handling

## Other Considerations

I don't have a preference on language. Please ask any clarification questions. Please think about the product idea and check to see if I'm missed anything. Please keep a summary of the work that you can consume on future sessions. If you need a localhost session of planka for testing, I can startup a dev environment.
