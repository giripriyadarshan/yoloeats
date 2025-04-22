import React, { useState } from 'react';
import axios from 'axios';

const UserProfileForm = () => {
    const [username, setUsername] = useState('');
    const [email, setEmail] = useState('');
    const [allergies, setAllergies] = useState(''); // Comma-separated input
    const [dietaryPreferences, setDietaryPreferences] = useState(''); // Comma-separated input

    const [isLoading, setIsLoading] = useState(false);
    const [errorMessage, setErrorMessage] = useState('');
    const [successMessage, setSuccessMessage] = useState('');

    const handleUsernameChange = (e) => {
        setUsername(e.target.value);
    };

    const handleEmailChange = (e) => {
        setEmail(e.target.value);
    };

    const handleAllergiesChange = (e) => {
        setAllergies(e.target.value);
    };

    const handleDietaryPreferencesChange = (e) => {
        setDietaryPreferences(e.target.value);
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setIsLoading(true);
        setErrorMessage('');
        setSuccessMessage('');

        // Backend API endpoint (ensure user-profile-service is running on port 8001)
        const API_URL = 'http://localhost:8001/api/v1/users';

        // apps/user-profile-service/src/models.rs
        const payload = {
            username: username,
            email: email,
            allergies: allergies.split(',')
                .map(item => item.trim())
                .filter(item => item !== ''),
            dietary_preferences: dietaryPreferences.split(',')
                .map(item => item.trim())
                .filter(item => item !== ''),
        };

        console.log('Submitting payload:', payload);

        try {
            const response = await axios.post(API_URL, payload);

            console.log('API Response:', response.data);
            setSuccessMessage('Profile created successfully!');

            setUsername('');
            setEmail('');
            setAllergies('');
            setDietaryPreferences('');

        } catch (error) {
            console.error('API Error:', error);
            const backendError = error.response?.data?.error || 'An unexpected error occurred.';
            setErrorMessage(`Failed to create profile: ${backendError}`);
        } finally {
            setIsLoading(false); // Reset loading state regardless of success or failure
        }
    };

    return (
        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '1rem', maxWidth: '400px', margin: 'auto' }}>
            <h2>User Profile</h2>

            {successMessage && <p style={{ color: 'green' }}>{successMessage}</p>}
            {errorMessage && <p style={{ color: 'red' }}>{errorMessage}</p>}

            <div>
                <label htmlFor="username">Username:</label>
                <input
                    type="text"
                    id="username"
                    value={username}
                    onChange={handleUsernameChange}
                    required
                    disabled={isLoading}
                    style={{ width: '100%', padding: '8px', boxSizing: 'border-box' }}
                />
            </div>

            <div>
                <label htmlFor="email">Email:</label>
                <input
                    type="email"
                    id="email"
                    value={email}
                    onChange={handleEmailChange}
                    required
                    disabled={isLoading}
                    style={{ width: '100%', padding: '8px', boxSizing: 'border-box' }}
                />
            </div>

            <div>
                <label htmlFor="allergies">Allergies (comma-separated):</label>
                <input
                    type="text"
                    id="allergies"
                    value={allergies}
                    onChange={handleAllergiesChange}
                    placeholder="e.g., peanuts, shellfish, gluten"
                    disabled={isLoading}
                    style={{ width: '100%', padding: '8px', boxSizing: 'border-box' }}
                />
            </div>

            <div>
                <label htmlFor="dietaryPreferences">Dietary Preferences (comma-separated):</label>
                <input
                    type="text"
                    id="dietaryPreferences"
                    value={dietaryPreferences}
                    onChange={handleDietaryPreferencesChange}
                    placeholder="e.g., vegetarian, vegan, low-carb"
                    disabled={isLoading}
                    style={{ width: '100%', padding: '8px', boxSizing: 'border-box' }}
                />
            </div>

            <button type="submit" disabled={isLoading} style={{ padding: '10px 15px', cursor: isLoading ? 'not-allowed' : 'pointer' }}>
                {isLoading ? 'Saving...' : 'Save Profile'}
            </button>
        </form>
    );
};

export default UserProfileForm;