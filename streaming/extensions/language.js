const acceptsLanguage = (chosenLanguages, language) => !Array.isArray(chosenLanguages) || chosenLanguages.includes(language || 'und');

export { acceptsLanguage };
